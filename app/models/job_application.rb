class JobApplication < ApplicationRecord
  include Compensation
  STATUSES = %w[saved applied interview offer rejected withdrawn].freeze
  # Explicit, finite transitions (plan §16).
  TRANSITIONS = {
    "saved" => %w[applied withdrawn],
    "applied" => %w[interview rejected withdrawn],
    "interview" => %w[interview offer rejected withdrawn],
    "offer" => %w[withdrawn],
    "rejected" => [],
    "withdrawn" => []
  }.freeze
  STATUS_LABELS = {
    "saved" => "Guardada", "applied" => "Candidatura enviada", "interview" => "Entrevista",
    "offer" => "Oferta", "rejected" => "Rejeitada", "withdrawn" => "Desisti"
  }.freeze
  # Title prefix for the task suggested by "Criar tarefa", depending on the current stage.
  TASK_TITLE_PREFIXES = {
    "saved" => "Candidatar-me", "applied" => "Follow-up", "interview" => "Preparar entrevista",
    "offer" => "Responder à oferta", "rejected" => "Rever candidatura", "withdrawn" => "Rever candidatura"
  }.freeze

  belongs_to :user
  belongs_to :job_listing, optional: true
  belongs_to :company, optional: true
  belongs_to :contact, optional: true
  has_many :job_application_events, -> { order(:occurred_at, :id) }, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :links, as: :linkable, dependent: :destroy
  has_many :shares, as: :shareable, dependent: :nullify
  has_many :email_messages, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself), default: "saved", validate: true

  normalizes :title, :company_name, with: ->(value) { value.strip }

  validates :title, presence: true, length: { maximum: 200 }
  validates :company_name, length: { maximum: 200 }
  validates :notes, length: { maximum: 10_000 }
  validates :job_listing_id, uniqueness: { scope: :user_id, message: "já tem uma candidatura" }, allow_nil: true
  validate :job_listing_belongs_to_user
  validate :contact_belongs_to_user

  # Links (or creates) the Company whose name matches company_name.
  before_save :link_company, if: -> { company_name_changed? || company_id.nil? }

  scope :recent, -> { order(updated_at: :desc) }
  scope :in_progress, -> { where(status: %w[saved applied interview offer]) }
  scope :search, ->(query) {
    next all if query.blank?
    pattern = "%#{sanitize_sql_like(query.to_s.strip)}%"
    # LOWER on both sides: LIKE is case-sensitive in PostgreSQL (not in SQLite).
    where("LOWER(job_applications.title) LIKE :q OR LOWER(job_applications.company_name) LIKE :q", q: pattern.downcase)
  }

  def self.status_label(status)
    STATUS_LABELS.fetch(status.to_s, status.to_s.humanize)
  end

  def status_label
    self.class.status_label(status)
  end

  def allowed_transitions
    TRANSITIONS.fetch(status, [])
  end

  def can_transition_to?(new_status)
    allowed_transitions.include?(new_status.to_s)
  end

  # rejected / withdrawn: nothing else can happen to this application.
  def closed?
    allowed_transitions.empty?
  end

  def url
    job_listing&.url
  end

  def suggested_task_title
    "#{TASK_TITLE_PREFIXES.fetch(status, 'Candidatura')}: #{title}".truncate(200)
  end

  private
    def link_company
      name = company_name.to_s.squish
      self.company = name.blank? ? nil : (user.companies.named(name).first || user.companies.create!(name: name))
    end

    def contact_belongs_to_user
      return if contact.nil?
      errors.add(:contact, "tem de ser teu") if contact.user_id != user_id
    end

    def job_listing_belongs_to_user
      return if job_listing.nil?
      errors.add(:job_listing, "tem de pertencer ao mesmo utilizador") if job_listing.user_id != user_id
    end
end
