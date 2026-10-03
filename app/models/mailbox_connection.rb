# Read-only access to one Gmail label where the user keeps replies from companies.
class MailboxConnection < ApplicationRecord
  STATUSES = %w[active error].freeze

  belongs_to :user
  has_many :email_messages, through: :user

  encrypts :access_token
  encrypts :refresh_token

  enum :status, STATUSES.index_by(&:itself), default: "active", validate: true

  def token_expired?(skew: 60.seconds)
    expires_at.present? && expires_at <= skew.from_now
  end

  def label_chosen?
    label_id.present?
  end

  def mark_error!(message)
    update!(status: "error", last_error: message.to_s.truncate(500))
  end

  # Never let tokens reach logs or inspect output.
  def inspect
    "#<MailboxConnection id: #{id}, user_id: #{user_id}, status: #{status}, label: #{label_name.inspect}>"
  end
  alias_method :to_s, :inspect
end
