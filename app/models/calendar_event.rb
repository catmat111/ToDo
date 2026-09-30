class CalendarEvent < ApplicationRecord
  SYNC_STATUSES = %w[pending synced error].freeze

  belongs_to :calendar_connection
  belongs_to :task, optional: true

  enum :sync_status, SYNC_STATUSES.index_by(&:itself), default: "pending", prefix: :sync, validate: true

  validates :external_event_id, uniqueness: { scope: :calendar_connection_id }, allow_nil: true
  validates :task_id, uniqueness: { scope: :calendar_connection_id }, allow_nil: true
  validate :task_belongs_to_connection_user

  scope :with_errors, -> { where(sync_status: "error") }
  scope :conflicts, -> { with_errors.where("calendar_events.last_error LIKE ?", "Conflito%") }

  def conflict?
    sync_error? && last_error.to_s.start_with?("Conflito")
  end

  private
    # A mapping can only point to a task owned by the connection's user.
    def task_belongs_to_connection_user
      return if task.nil? || calendar_connection.nil?
      errors.add(:task, "tem de pertencer ao dono da ligação") if task.user_id != calendar_connection.user_id
    end
end
