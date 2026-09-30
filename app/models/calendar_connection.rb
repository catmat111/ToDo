class CalendarConnection < ApplicationRecord
  PROVIDERS = %w[google].freeze
  STATUSES = %w[active error revoked].freeze

  belongs_to :user
  has_many :calendar_events, dependent: :destroy

  # OAuth tokens are encrypted at rest and never leave the server (plan §13).
  encrypts :access_token
  encrypts :refresh_token

  enum :status, STATUSES.index_by(&:itself), default: "active", validate: true

  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :user_id }
  validates :calendar_id, presence: true, length: { maximum: 255 }

  def token_expired?(skew: 60.seconds)
    expires_at.present? && expires_at <= skew.from_now
  end

  def mark_error!(message)
    update!(status: "error", last_error: message.to_s.truncate(500))
  end

  # Counts of event mappings per sync status: { "synced" => 3, "error" => 1, "pending" => 0 }.
  def event_counts
    counts = calendar_events.group(:sync_status).count
    CalendarEvent::SYNC_STATUSES.index_with { |status| counts.fetch(status, 0) }
  end

  # Never let tokens reach logs or inspect output.
  def inspect
    "#<CalendarConnection id: #{id}, user_id: #{user_id}, provider: #{provider}, status: #{status}>"
  end
  alias_method :to_s, :inspect
end
