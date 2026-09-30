class AuditLog < ApplicationRecord
  SENSITIVE_KEYS = /token|password|secret|cookie|authorization/i

  belongs_to :user, optional: true

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # AuditLog.record("task.completed", resource: task, user: Current.user, from: "pending")
  # Never raises: auditing must not break the user's action.
  def self.record(action, resource: nil, user: Current.user, **metadata)
    create!(
      action: action,
      user: user,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      metadata: redact(metadata)
    )
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[audit] failed to record #{action}: #{e.class}")
    nil
  end

  def self.redact(hash)
    hash.to_h.transform_keys(&:to_s).to_h do |key, value|
      [ key, key.match?(SENSITIVE_KEYS) ? "[FILTERED]" : value ]
    end
  end
end
