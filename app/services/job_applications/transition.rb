module JobApplications
  # Moves an application to a new status following JobApplication::TRANSITIONS (plan §16).
  #
  #   JobApplications::Transition.call(application, to: "applied", create_follow_up: true)
  #   JobApplications::Transition.call(application, to: "interview", interview_at: 3.days.from_now)
  #
  # Every successful transition records a JobApplicationEvent for the new status, so the history
  # always explains how the application reached where it is. Optional side effects:
  # - applied + create_follow_up  -> "Follow-up: <title>" job task due in 7 days;
  # - interview + interview_at    -> "Entrevista: <title>" task (1h slot) with a reminder the day before.
  # Everything happens in one transaction: either all of it is saved or nothing is.
  class Transition
    FOLLOW_UP_AFTER = 7.days
    INTERVIEW_DURATION = 1.hour
    INTERVIEW_REMINDER_BEFORE = 1.day

    def self.call(...)
      new(...).call
    end

    def initialize(job_application, to:, occurred_at: Time.current, notes: nil, create_follow_up: false, interview_at: nil)
      @job_application = job_application
      @to = to.to_s
      @occurred_at = parse_time(occurred_at) || Time.current
      @notes = notes.to_s.strip.presence
      @create_follow_up = ActiveModel::Type::Boolean.new.cast(create_follow_up) || false
      @interview_at = parse_time(interview_at)
    end

    def call
      from = job_application.status
      if (error = rejection_reason(from))
        return failure(error)
      end

      event = nil
      tasks = []
      ActiveRecord::Base.transaction do
        job_application.status = to
        job_application.applied_at = occurred_at if to == "applied"
        job_application.save!

        event = job_application.job_application_events.create!(
          event_type: to, occurred_at: occurred_at, notes: event_notes
        )
        tasks << create_follow_up_task if to == "applied" && create_follow_up
        tasks << create_interview_task if to == "interview" && interview_at
      end

      AuditLog.record("job_application.status_changed", resource: job_application, user: job_application.user,
                      from: from, to: to, event_id: event.id, task_ids: tasks.map(&:id))
      Result.new(success: true, job_application: job_application, event: event, tasks: tasks)
    rescue ActiveRecord::RecordInvalid => e
      message = e.record.errors.full_messages.to_sentence
      job_application.reload # the transaction was rolled back; drop the in-memory status change
      failure(message)
    end

    private
      attr_reader :job_application, :to, :occurred_at, :notes, :create_follow_up, :interview_at

      def rejection_reason(from)
        return "Estado desconhecido: #{to.presence || 'vazio'}." unless JobApplication::STATUSES.include?(to)
        return nil if job_application.can_transition_to?(to)

        from_label = JobApplication.status_label(from)
        if job_application.closed?
          "A candidatura está encerrada (#{from_label}) e já não pode mudar de estado."
        else
          "Não é possível passar de «#{from_label}» para «#{JobApplication.status_label(to)}»."
        end
      end

      def event_notes
        return notes unless to == "interview" && interview_at
        scheduled = "Entrevista marcada para #{I18n.l(interview_at.in_time_zone, format: '%d/%m/%Y às %H:%M')}."
        [ scheduled, notes ].compact.join("\n")
      end

      def create_follow_up_task
        build_task(title: "Follow-up: #{job_application.title}",
                   due_at: Time.current + FOLLOW_UP_AFTER,
                   description: "Verificar se houve resposta à candidatura.").tap(&:save!)
      end

      def create_interview_task
        task = build_task(title: "Entrevista: #{job_application.title}",
                          starts_at: interview_at, due_at: interview_at + INTERVIEW_DURATION,
                          description: notes)
        task.save!
        remind_at = interview_at - INTERVIEW_REMINDER_BEFORE
        task.reminders.create!(remind_at: remind_at) if remind_at.future?
        task
      end

      def build_task(title:, **attrs)
        job_application.user.tasks.new(title: title.truncate(200), task_type: "job",
                                       job_application: job_application, **attrs)
      end

      def failure(message)
        Result.new(success: false, job_application: job_application, error: message)
      end

      def parse_time(value)
        case value
        when nil, "" then nil
        when String then Time.zone.parse(value)
        else value.respond_to?(:in_time_zone) ? value.in_time_zone : nil
        end
      rescue ArgumentError
        nil
      end
  end
end
