class Reminder < ApplicationRecord
  CHANNELS = %w[in_app email].freeze
  CHANNEL_LABELS = { "in_app" => "Na app", "email" => "Email" }.freeze
  MAX_ATTEMPTS = 5
  ERROR_MAX_LENGTH = 500

  belongs_to :task

  enum :channel, CHANNELS.index_by(&:itself), default: "in_app", validate: { message: "não é válido" }

  validates :remind_at, presence: { message: "tem de ser indicada" }
  validates :remind_at, uniqueness: { scope: [ :task_id, :channel ], message: "já tem um lembrete marcado neste canal" },
                        if: :remind_at?
  validate :remind_at_in_the_future, on: :create
  validate :task_is_open, on: :create

  scope :pending, -> { where(sent_at: nil).where(attempts: ...MAX_ATTEMPTS) }
  scope :due, ->(now = Time.current) { pending.where(remind_at: ..now) }
  scope :upcoming, ->(now = Time.current) { pending.where(remind_at: now..).order(:remind_at) }
  scope :failed, -> { where(sent_at: nil).where(attempts: MAX_ATTEMPTS..) }

  def sent?
    sent_at.present?
  end

  # Gave up after too many failed deliveries.
  def failed?
    !sent? && attempts >= MAX_ATTEMPTS
  end

  def channel_label
    CHANNEL_LABELS.fetch(channel, channel.to_s.humanize)
  end

  # Atomically marks the reminder as sent. Returns false when another run already
  # claimed it, so running the dispatcher twice never delivers twice.
  def claim!(now = Time.current)
    claimed = self.class.where(id: id, sent_at: nil).update_all(sent_at: now, updated_at: now) == 1
    self.sent_at = now if claimed
    claimed
  end

  # Undoes the claim and records the failure so the reminder is retried
  # (until MAX_ATTEMPTS). The stored error never includes credentials.
  def record_failure!(error, now = Time.current)
    message = self.class.sanitize_error(error)
    self.class.where(id: id).update_all([ "sent_at = NULL, attempts = attempts + 1, last_error = ?, updated_at = ?", message, now ])
    reload
  end

  def self.sanitize_error(error)
    text = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
    text.gsub(/(token|password|secret|key|authorization)(["']?\s*[:=]\s*)\S+/i, '\1\2[FILTERED]')
        .truncate(ERROR_MAX_LENGTH)
  end

  private
    def remind_at_in_the_future
      return if remind_at.blank?
      errors.add(:remind_at, "tem de ser no futuro") if remind_at <= Time.current
    end

    def task_is_open
      return if task.nil? || task.open?
      errors.add(:task, "já está concluída ou cancelada")
    end
end
