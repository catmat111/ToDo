module Reminders
  # Turns due reminders into notifications (and emails for the email channel).
  #
  #   Reminders::Dispatcher.call                 # => #<Result delivered=2 skipped=1 failed=0>
  #
  # Every reminder is claimed atomically before anything is delivered, so two
  # overlapping runs never notify twice. A failure undoes the claim and records the
  # error, and the reminder is retried on the next run until Reminder::MAX_ATTEMPTS.
  class Dispatcher
    Result = Struct.new(:delivered, :skipped, :failed) do
      def total = delivered + skipped + failed
    end

    def self.call(now: Time.current)
      new(now: now).call
    end

    def initialize(now: Time.current)
      @now = now
      @result = Result.new(0, 0, 0)
    end

    def call
      Reminder.due(now).includes(task: :user).find_each { |reminder| process(reminder) }
      result
    end

    private
      attr_reader :now, :result

      def process(reminder)
        return unless reminder.claim!(now)

        task = reminder.task
        unless deliverable?(task)
          # Completed, cancelled or archived tasks: consume the reminder silently.
          result.skipped += 1
          return
        end

        deliver(reminder, task)
        result.delivered += 1
      rescue StandardError => error
        reminder.record_failure!(error, now)
        Rails.logger.warn("[reminders] reminder ##{reminder.id} failed (attempt #{reminder.attempts}): #{error.class}")
        result.failed += 1
      end

      def deliverable?(task)
        task.present? && task.open? && !task.archived?
      end

      def deliver(reminder, task)
        ActiveRecord::Base.transaction do
          notification = Notification.create!(
            user: task.user,
            notifiable: task,
            notification_type: "reminder",
            title: "Lembrete: #{task.title}".truncate(255),
            body: body_for(task)
          )
          NotificationMailer.reminder(notification).deliver_later if reminder.email?
          reminder.update_columns(last_error: nil) if reminder.last_error.present?
        end
      end

      def body_for(task)
        return "Tens um lembrete para esta tarefa." if task.due_at.blank?

        due = task.due_at.in_time_zone(task.user.time_zone)
        when_text = I18n.l(due, format: "%d/%m/%Y às %H:%M")
        if due < now
          "O prazo terminou a #{when_text}."
        else
          "O prazo termina a #{when_text}."
        end
      end
  end
end
