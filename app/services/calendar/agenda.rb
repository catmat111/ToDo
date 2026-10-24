module Calendar
  # The user's non-archived tasks placed on the days of a Period, by due_at
  # (falling back to starts_at when a task only has a start), plus their events
  # (an event lasting several days shows on each of them).
  #
  # Open tasks with a deadline are drawn as a line (a Span) over every day from their
  # start (starts_at, else the day they were created) to the deadline. Spans are laid
  # out in lanes per week so each line keeps its height from day to day.
  class Agenda
    Span = Data.define(:task, :first_day, :last_day) do
      def covers?(date) = date.between?(first_day, last_day)
    end
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

    # Tasks shown on their day alone (open tasks with a deadline are spans instead).
    def tasks_on(date)
      tasks_by_day.fetch(date, []).reject { |task| span_task_ids.include?(task.id) }
    end

    def spans
      @spans ||= begin
        range = @period.time_range
        @user.tasks.active.open.where(due_at: range.begin..)
             .where("COALESCE(tasks.starts_at, tasks.created_at) <= ?", range.end)
             .order(:due_at, :id).map do |task|
          first = (task.starts_at || task.created_at).in_time_zone.to_date
          last = task.due_at.in_time_zone.to_date
          Span.new(task: task, first_day: [ first, last ].min, last_day: last)
        end
      end
    end

    # The spans crossing a week, each in a lane (row) that it keeps all week: an array of
    # lanes, each an array of spans that don't overlap. Longer spans get the top lanes.
    def lanes(week)
      @lanes ||= {}
      @lanes[week.first] ||= begin
        crossing = spans.select { |span| span.first_day <= week.last && span.last_day >= week.first }
        crossing.sort_by { |span| [ span.first_day, -(span.last_day - span.first_day) ] }.each_with_object([]) do |span, lanes|
          lane = lanes.find { |spans_in_lane| spans_in_lane.none? { |other| other.first_day <= span.last_day && other.last_day >= span.first_day } }
          lane ? lane << span : lanes << [ span ]
        end
      end
    end

    def spans_on(date)
      spans.select { |span| span.covers?(date) }
    end

    def events
      @events ||= @user.events.overlapping(@period.time_range).chronological.to_a
    end

    def events_in_focus
      @events_in_focus ||= events.select { |event| (event.first_day..event.last_day).any? { |day| @period.in_focus?(day) } }
    end

    def events_on(date)
      events.select { |event| event.on?(date) }
    end

    def span_task_ids
      @span_task_ids ||= spans.map { |span| span.task.id }.to_set
    end

    def self.date_of(task)
      (task.due_at || task.starts_at).in_time_zone.to_date
    end

    def self.time_of(task)
      task.due_at || task.starts_at
    end
  end
end
