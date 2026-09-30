module Calendar
  # Maps a Task to the Google Calendar event payload.
  #
  #   starts_at + due_at -> starts_at .. due_at
  #   only due_at        -> due_at - 30 min .. due_at
  #   only starts_at     -> starts_at .. starts_at + 30 min
  #
  # Times are sent in the user's own time zone; the task id travels in a private
  # extended property so events can always be traced back to the app.
  class EventMapper
    DEFAULT_DURATION = 30.minutes
    COMPLETED_PREFIX = "✓ ".freeze

    def self.call(task)
      new(task).call
    end

    # [start, end] for a task, or nil when it has no dates.
    def self.times_for(task)
      start_at = task.starts_at
      end_at = task.due_at
      return nil if start_at.nil? && end_at.nil?

      start_at ||= end_at - DEFAULT_DURATION
      end_at ||= start_at + DEFAULT_DURATION
      [ start_at.change(usec: 0), end_at.change(usec: 0) ]
    end

    def initialize(task)
      @task = task
    end

    def call
      start_at, end_at = self.class.times_for(@task)
      raise ArgumentError, "A tarefa não tem datas para sincronizar" if start_at.nil?

      {
        summary: summary,
        description: @task.description.to_s,
        start: { dateTime: start_at.in_time_zone(zone).iso8601, timeZone: zone_name },
        end: { dateTime: end_at.in_time_zone(zone).iso8601, timeZone: zone_name },
        extendedProperties: { private: { todo_task_id: @task.id.to_s } }
      }
    end

    private
      def summary
        @task.completed? ? "#{COMPLETED_PREFIX}#{@task.title}" : @task.title
      end

      def zone
        @task.user.time_zone
      end

      def zone_name
        zone.tzinfo.name
      end
  end
end
