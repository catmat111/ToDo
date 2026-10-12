module NotificationsHelper
  NOTIFICATION_ICONS = {
    "reminder" => :bell, "task_due" => :clock, "application" => :briefcase,
    "calendar" => :calendar, "share" => :user, "system" => :settings
  }.freeze

  # Path of the record a notification points to, or nil when there is none
  # (or it was deleted). Only records the app can show are linked.
  def notifiable_path(notification)
    record = notification.notifiable
    case record
    when Task then task_path(record)
    when JobApplication then job_application_path(record)
    when JobListing then job_listing_path(record)
    when JobSearch then job_search_path(record)
    when CalendarConnection then calendar_connection_path
    when Share then shares_path(tab: (notification.user_id == record.sender_id ? "sent" : nil))
    when MailboxConnection then email_messages_path
    when nil then job_applications_path if notification.notification_type == "application"
    end
  end

  def notifiable_label(notification)
    case notification.notifiable
    when Task then "Ver tarefa"
    when JobApplication then "Ver candidatura"
    when JobListing then "Ver vaga"
    when JobSearch then "Ver pesquisa"
    when CalendarConnection then "Ver ligação"
    when Share then "Ver partilhas"
    when MailboxConnection then "Ver respostas"
    when nil then "Ver candidaturas" if notification.notification_type == "application"
    end
  end

  def notification_icon(notification)
    type = notification.notification_type
    tag.span(icon(NOTIFICATION_ICONS.fetch(type, :bell)),
             class: "notification-icon notification-icon--#{type.to_s.dasherize}",
             title: notification.type_label)
  end

  def notification_time(notification)
    tag.time("há #{time_ago_in_words(notification.created_at)}",
             datetime: notification.created_at.iso8601, title: format_datetime(notification.created_at, format: :long))
  end

  def reminder_channel_badge(reminder)
    tag.span(reminder.channel_label, class: "badge badge--type")
  end

  def reminder_state_badge(reminder)
    if reminder.sent?
      status_badge("completed", "Enviado")
    elsif reminder.failed?
      status_badge("error", "Falhou")
    elsif reminder.attempts.positive?
      status_badge("in_progress", "A tentar de novo")
    else
      status_badge("pending", "Agendado")
    end
  end

  # [label, remind_at] presets relative to the task's deadline that are still in the future
  # and not already scheduled.
  def reminder_presets(task)
    return [] if task.due_at.blank?

    taken = task.reminders.select(&:in_app?).map { |r| r.remind_at.to_i }
    [
      [ "No prazo", 0.seconds ], [ "15 min antes", 15.minutes ], [ "1 hora antes", 1.hour ],
      [ "1 dia antes", 1.day ], [ "1 semana antes", 1.week ]
    ].filter_map do |label, offset|
      at = task.due_at - offset
      [ label, at ] if at.future? && taken.exclude?(at.to_i)
    end
  end
end
