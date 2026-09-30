module Calendar
  # The user's non-archived tasks placed on the days of a Period, by due_at
  # (falling back to starts_at when a task only has a start).
  class Agenda
    def initialize(user:, period:)
      @user = user
      @period = period
    end

    def tasks
      @tasks ||= begin
        range = @period.time_range
        scope = @user.tasks.active
        scope.where(due_at: range)
             .or(scope.where(due_at: nil, starts_at: range))
             .includes(calendar_events: :calendar_connection)
             .order(Arel.sql("COALESCE(tasks.due_at, tasks.starts_at)"), :id)
             .to_a
      end
    end

    # Tasks of the month/week itself (excludes the neighbouring days a month grid shows).
    def tasks_in_focus
      @tasks_in_focus ||= tasks.select { |task| @period.in_focus?(self.class.date_of(task)) }
    end

    def tasks_by_day
      @tasks_by_day ||= tasks.group_by { |task| self.class.date_of(task) }
    end

    def tasks_on(date)
      tasks_by_day.fetch(date, [])
    end

    def self.date_of(task)
      (task.due_at || task.starts_at).in_time_zone.to_date
    end

    def self.time_of(task)
      task.due_at || task.starts_at
    end
  end
end
