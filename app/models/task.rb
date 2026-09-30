class Task < ApplicationRecord
  TYPES = %w[project routine exam delivery job other].freeze
  STATUSES = %w[pending in_progress completed cancelled].freeze
  PRIORITIES = { 0 => "baixa", 1 => "normal", 2 => "alta", 3 => "urgente" }.freeze
  MAX_DEPTH = 5

  # Explicit, finite status transitions (plan §16). Reopening always goes back to "pending".
  TRANSITIONS = {
    "pending" => %w[in_progress completed cancelled],
    "in_progress" => %w[completed cancelled pending],
    "completed" => %w[pending],
    "cancelled" => %w[pending]
  }.freeze

  TYPE_LABELS = {
    "project" => "Projeto", "routine" => "Rotina", "exam" => "Exame",
    "delivery" => "Entrega", "job" => "Emprego", "other" => "Outro"
  }.freeze
  STATUS_LABELS = {
    "pending" => "Pendente", "in_progress" => "Em curso", "completed" => "Concluída", "cancelled" => "Cancelada"
  }.freeze

  include CalendarSyncable

  belongs_to :user
  belongs_to :parent_task, class_name: "Task", optional: true, inverse_of: :subtasks
  belongs_to :job_application, optional: true

  has_many :subtasks, -> { order(:position, :id) }, class_name: "Task",
           foreign_key: :parent_task_id, dependent: :destroy, inverse_of: :parent_task
  has_many :task_tags, dependent: :destroy
  has_many :tags, through: :task_tags
  has_many :reminders, -> { order(:remind_at) }, dependent: :destroy
  has_many :calendar_events, dependent: :nullify
  has_many :links, as: :linkable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :nullify
  has_one :recurrence, class_name: "TaskRecurrence", dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), default: "pending", validate: true
  enum :task_type, TYPES.index_by(&:itself), default: "other", prefix: :type, validate: true

  # Virtual: optional first reminder chosen in the "new task" form (Tasks::Create turns it into a Reminder).
  attribute :reminder_at, :datetime

  validates :title, presence: true, length: { maximum: 200 }
  validates :priority, inclusion: { in: PRIORITIES.keys }
  validate :due_after_start
  validate :parent_belongs_to_same_user
  validate :parent_is_not_self_or_descendant
  validate :job_application_belongs_to_same_user
  validate :status_transition_allowed, on: :update
  validate :reminder_in_future, on: :create

  before_save :sync_completed_at

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :root_level, -> { where(parent_task_id: nil) }
  scope :open, -> { where(status: %w[pending in_progress]) }
  scope :overdue, -> { open.where(due_at: ...Time.current) }
  scope :due_between, ->(from, to) { where(due_at: from..to) }
  scope :ordered, -> { order(Arel.sql("CASE WHEN tasks.due_at IS NULL THEN 1 ELSE 0 END"), :due_at, priority: :desc, id: :desc) }

  def self.type_label(type)
    TYPE_LABELS.fetch(type.to_s, type.to_s.humanize)
  end

  def self.status_label(status)
    STATUS_LABELS.fetch(status.to_s, status.to_s.humanize)
  end

  def self.priority_label(priority)
    PRIORITIES.fetch(priority.to_i, "normal").capitalize
  end

  def type_label
    self.class.type_label(task_type)
  end

  def status_label
    self.class.status_label(status)
  end

  def open?
    pending? || in_progress?
  end

  def closed?
    completed? || cancelled?
  end

  def archived?
    archived_at.present?
  end

  def overdue?
    open? && due_at.present? && due_at < Time.current
  end

  def priority_label
    PRIORITIES.fetch(priority, "normal")
  end

  def allowed_transitions
    TRANSITIONS.fetch(status, [])
  end

  def can_transition_to?(new_status)
    allowed_transitions.include?(new_status.to_s)
  end

  # [completed, total] over direct subtasks (cancelled ones don't count).
  def progress
    relevant = subtasks.reject(&:cancelled?)
    [ relevant.count(&:completed?), relevant.size ]
  end

  def progress_percent
    done, total = progress
    total.zero? ? (completed? ? 100 : 0) : (done * 100 / total)
  end

  def all_subtasks_completed?
    done, total = progress
    total.positive? && done == total
  end

  # Parent completion is always a human decision: we only suggest it.
  def suggest_completion?
    open? && all_subtasks_completed?
  end

  def ancestors
    list = []
    node = parent_task
    while node && list.size <= MAX_DEPTH
      list << node
      node = node.parent_task
    end
    list
  end

  # Loads the direct subtasks with what their list rows need; returns them as an Array.
  def preload_subtasks
    ActiveRecord::Associations::Preloader.new(records: [ self ], associations: { subtasks: [ :tags, :subtasks, :recurrence ] }).call
    subtasks.to_a
  end

  # Ids of every task below this one (breadth-first, bounded by MAX_DEPTH).
  def descendant_ids
    return [] unless persisted?
    ids = []
    frontier = [ id ]
    (MAX_DEPTH + 1).times do
      frontier = Task.where(parent_task_id: frontier).where.not(id: ids + [ id ]).pluck(:id)
      break if frontier.empty?
      ids.concat(frontier)
    end
    ids
  end

  private
    def due_after_start
      return if starts_at.blank? || due_at.blank?
      errors.add(:due_at, "não pode ser anterior ao início") if due_at < starts_at
    end

    def parent_belongs_to_same_user
      return if parent_task.nil?
      errors.add(:parent_task, "tem de pertencer ao mesmo utilizador") if parent_task.user_id != user_id
    end

    # Walks up from the chosen parent; if we meet ourselves the hierarchy would form a cycle.
    def parent_is_not_self_or_descendant
      return if parent_task.nil?
      if persisted? && parent_task_id == id
        errors.add(:parent_task, "não pode ser a própria tarefa")
        return
      end
      depth = 0
      node = parent_task
      while node
        if persisted? && node.id == id
          errors.add(:parent_task, "criaria um ciclo na hierarquia")
          return
        end
        depth += 1
        break errors.add(:parent_task, "excede a profundidade máxima (#{MAX_DEPTH})") if depth >= MAX_DEPTH
        node = node.parent_task
      end
    end

    def job_application_belongs_to_same_user
      return if job_application.nil?
      errors.add(:job_application, "tem de pertencer ao mesmo utilizador") if job_application.user_id != user_id
    end

    def status_transition_allowed
      return unless will_save_change_to_status?
      from = status_in_database
      return if STATUSES.exclude?(status) || TRANSITIONS.fetch(from, []).include?(status)
      errors.add(:status, "não pode passar de «#{self.class.status_label(from)}» para «#{status_label}»")
    end

    def reminder_in_future
      return if reminder_at.blank?
      errors.add(:reminder_at, "tem de ser no futuro") if reminder_at <= Time.current
    end

    # completed_at mirrors the status: set when the task becomes completed, cleared otherwise.
    def sync_completed_at
      if completed?
        self.completed_at = Time.current if will_save_change_to_status? || completed_at.nil?
      else
        self.completed_at = nil
      end
    end
end
