# Runs every hour (config/recurring.yml). Creates one "task_due" notification per
# open task whose deadline falls within the next WINDOW; never twice for the same task.
class DueTaskNotificationJob < ApplicationJob
  queue_as :default

  WINDOW = 24.hours

  def perform(now: Time.current)
    created = 0
    due_soon(now).includes(:user).find_each do |task|
      created += 1 if notify(task, now)
    end
    created
  end

  private
    def due_soon(now)
      already_notified = Notification.of_type("task_due").where(notifiable_type: "Task").where.not(notifiable_id: nil).select(:notifiable_id)
      Task.active.open.where(due_at: now..(now + WINDOW)).where.not(id: already_notified)
    end

    def notify(task, now)
      due = task.due_at.in_time_zone(task.user.time_zone)
      Notification.create!(
        user: task.user,
        notifiable: task,
        notification_type: "task_due",
        title: "Prazo a aproximar-se: #{task.title}".truncate(255),
        body: "Esta tarefa termina #{due_phrase(due, now.in_time_zone(task.user.time_zone))}."
      )
      true
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("[due_tasks] could not notify task ##{task.id}: #{error.class}")
      false
    end

    def due_phrase(due, now)
      time = I18n.l(due, format: "%H:%M")
      case due.to_date
      when now.to_date then "hoje às #{time}"
      when now.to_date + 1 then "amanhã às #{time}"
      else "a #{I18n.l(due, format: '%d/%m/%Y às %H:%M')}"
      end
    end
end
