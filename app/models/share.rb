# Something a user sends to another user (a task to do, a job listing or an
# application to look at). The recipient accepts or declines it; accepting
# creates a COPY in the recipient's own account, so each user still only ever
# sees their own records.
class Share < ApplicationRecord
  SHAREABLE_TYPES = %w[Task JobListing JobApplication].freeze
  STATUSES = %w[pending accepted declined].freeze
  STATUS_LABELS = { "pending" => "Pendente", "accepted" => "Aceite", "declined" => "Recusada" }.freeze
  KIND_LABELS = { "Task" => "Tarefa", "JobListing" => "Vaga", "JobApplication" => "Candidatura" }.freeze

  belongs_to :sender, class_name: "User"
  belongs_to :recipient, class_name: "User"
  belongs_to :shareable, polymorphic: true, optional: true
  belongs_to :copy, polymorphic: true, optional: true

  enum :status, STATUSES.index_by(&:itself), default: "pending", validate: true

  normalizes :message, with: ->(m) { m.strip.presence }

  # Only checked on create: if the original is deleted later, shareable_* become NULL.
  validates :shareable_type, inclusion: { in: SHAREABLE_TYPES }, on: :create
  validates :title, presence: true
  validates :message, length: { maximum: 1000 }
  validate :not_to_self
  validate :shareable_belongs_to_sender, on: :create

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def kind_label
    KIND_LABELS.fetch(shareable_type, "Item")
  end

  def status_label
    STATUS_LABELS.fetch(status, status)
  end

  private
    def not_to_self
      errors.add(:recipient, "não podes ser tu") if recipient_id.present? && recipient_id == sender_id
    end

    def shareable_belongs_to_sender
      return if shareable.nil?
      errors.add(:shareable, "tem de ser teu") if shareable.user_id != sender_id
    end
end
