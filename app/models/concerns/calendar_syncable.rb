# Hooks a Task into the Google Calendar integration without making task
# management depend on it (plan §2: the app must work if the integration is down).
#
# * After a task is created/updated, a CalendarTaskSyncJob is enqueued when the
#   owner has an active Google connection, the task syncs (or just stopped
#   syncing) and a calendar-relevant attribute changed.
# * Deletion policy: deleting a task deletes its Google Calendar event. The
#   external ids are collected before the destroy and a CalendarEventDeleteJob
#   is enqueued per event once the transaction commits.
#
# Every callback is cheap (one indexed query at most) and never raises.
module CalendarSyncable
  extend ActiveSupport::Concern

  SYNC_ATTRIBUTES = %w[title description starts_at due_at status sync_to_calendar archived_at].freeze
  SUPPRESS_KEY = :calendar_syncable_suppressed

  # Runs the block without enqueuing calendar jobs (used when importing changes
  # that came *from* Google, so they don't echo back).
  def self.without_sync
    previous = ActiveSupport::IsolatedExecutionState[SUPPRESS_KEY]
    ActiveSupport::IsolatedExecutionState[SUPPRESS_KEY] = true
    yield
  ensure
    ActiveSupport::IsolatedExecutionState[SUPPRESS_KEY] = previous
  end

  def self.suppressed?
    ActiveSupport::IsolatedExecutionState[SUPPRESS_KEY].present?
  end

  included do
    scope :calendar_eligible, -> {
      where(sync_to_calendar: true, archived_at: nil)
        .where("tasks.due_at IS NOT NULL OR tasks.starts_at IS NOT NULL")
    }

    before_destroy :collect_calendar_events_for_cleanup, prepend: true
    after_commit :enqueue_calendar_sync, on: %i[create update]
    after_destroy_commit :enqueue_calendar_event_cleanup
  end

  # Should this task have an event in Google Calendar?
  def calendar_eligible?
    sync_to_calendar? && archived_at.nil? && (due_at.present? || starts_at.present?)
  end

  private
    def enqueue_calendar_sync
      return if CalendarSyncable.suppressed?
      return unless sync_to_calendar? || saved_change_to_sync_to_calendar?
      return unless saved_changes.keys.intersect?(SYNC_ATTRIBUTES)
      return unless google_calendar_active?

      CalendarTaskSyncJob.perform_later(id)
    rescue StandardError => e
      Rails.logger.warn("[calendar] could not enqueue sync for task #{id}: #{e.class}")
    end

    def collect_calendar_events_for_cleanup
      @calendar_events_to_delete = CalendarEvent.where(task_id: id).where.not(external_event_id: nil)
                                                .pluck(:calendar_connection_id, :external_event_id)
    rescue StandardError => e
      Rails.logger.warn("[calendar] could not collect events for task #{id}: #{e.class}")
      @calendar_events_to_delete = []
    end

    def enqueue_calendar_event_cleanup
      Array(@calendar_events_to_delete).each do |connection_id, external_event_id|
        CalendarEventDeleteJob.perform_later(connection_id, external_event_id)
      end
    rescue StandardError => e
      Rails.logger.warn("[calendar] could not enqueue event cleanup for task #{id}: #{e.class}")
    end

    def google_calendar_active?
      CalendarConnection.exists?(user_id: user_id, provider: "google", status: "active")
    end
end
