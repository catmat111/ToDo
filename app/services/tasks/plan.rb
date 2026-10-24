module Tasks
  # Moves a task between "today" and a tag's backlog — what dragging does on the home page.
  #
  #   Tasks::Plan.call(task, to: "today")                 # due today (keeps its hour if already today)
  #   Tasks::Plan.call(task, to: "backlog", tag: estudo)  # no due date, in that tag
  class Plan
    def self.call(...)
      new(...).call
    end

    def initialize(task, to:, tag: nil)
      @task = task
      @to = to.to_s
      @tag = tag
    end

    def call
      case @to
      when "today" then Update.call(@task, params: today_params)
      when "backlog"
        return failure("Escolhe uma etiqueta.") unless @tag
        Update.call(@task, params: { due_at: nil, tag_ids: (@task.tag_ids | [ @tag.id ]).map(&:to_s) })
      else failure("Destino desconhecido.")
      end
    end

    private
      def today_params
        today = Time.zone.today
        due = @task.due_at&.in_time_zone&.to_date == today ? @task.due_at : Time.zone.now.end_of_day
        params = { due_at: due }
        params[:starts_at] = nil if @task.starts_at && @task.starts_at > due # a start after the new deadline would be invalid
        params
      end

      def failure(message)
        Result.new(success: false, task: @task, error: message)
      end
  end
end
