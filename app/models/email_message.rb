# An email from the user's job-replies Gmail label, with the outcome the app detected
# and the application it probably belongs to. Nothing changes until the user confirms.
class EmailMessage < ApplicationRecord
  OUTCOMES = {
    "rejected" => "Rejeição", "interview" => "Entrevista / próxima fase", "offer" => "Oferta",
    "received" => "Candidatura recebida", "unknown" => "Outro"
  }.freeze
  # Which application status each outcome leads to (nil = just add it to the history).
  OUTCOME_STATUS = { "rejected" => "rejected", "interview" => "interview", "offer" => "offer" }.freeze
  REVIEW_STATUSES = %w[pending confirmed ignored].freeze

  belongs_to :user
  belongs_to :job_application, optional: true

  enum :review_status, REVIEW_STATUSES.index_by(&:itself), default: "pending", validate: true

  validates :external_id, presence: true, uniqueness: { scope: :user_id }
  validates :outcome, inclusion: { in: OUTCOMES.keys }
  validate :job_application_belongs_to_user

  scope :recent, -> { order(received_at: :desc, id: :desc) }

  def outcome_label
    OUTCOMES.fetch(outcome, "Outro")
  end

  def sender
    from_name.presence || from_email
  end

  private
    def job_application_belongs_to_user
      return if job_application.nil?
      errors.add(:job_application, "tem de ser tua") if job_application.user_id != user_id
    end
end
