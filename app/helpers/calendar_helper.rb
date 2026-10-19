module CalendarHelper
  CALENDAR_SYNC_LABELS = {
    "synced" => "Google: sincronizada",
    "pending" => "Google: a sincronizar",
    "error" => "Google: erro"
  }.freeze

  CALENDAR_CONNECTION_LABELS = { "active" => "Ativa", "error" => "Erro", "revoked" => "Revogada" }.freeze

  def calendar_connection_badge(connection)
    return tag.span("Não ligada", class: "badge") if connection.nil?
    status_badge(connection.status, CALENDAR_CONNECTION_LABELS[connection.status])
  end

  # Small badge with the Google sync state of a task; nil when the task does not
  # sync or the user has no Google connection.
  def calendar_task_sync_badge(task)
    return unless task.sync_to_calendar?

    event = task.calendar_events.find { |calendar_event| calendar_event.calendar_connection&.provider == "google" }
    connection = event&.calendar_connection || Current.user&.google_calendar
    return if connection.nil? || connection.user_id != task.user_id

    state, label, title = calendar_sync_state(task, event, connection)
    tag.span(class: "badge badge--#{state} calendar-sync-badge", title: title) do
      safe_join([ icon(:calendar, size: 13), label ], " ")
    end
  end

  def calendar_weekday_names
    Calendar::Period::WEEKDAY_NAMES
  end

  def calendar_full_date(date)
    weekday = Calendar::Period::WEEKDAY_FULL_NAMES[date.cwday - 1]
    "#{weekday}, #{date.day} de #{Calendar::Period::MONTH_NAMES[date.month - 1]} de #{date.year}"
  end

  def calendar_day_classes(period, date)
    [
      "calendar-day",
      ("calendar-day--outside" unless period.in_focus?(date)),
      ("calendar-day--today" if period.today?(date)),
      ("calendar-day--weekend" if date.saturday? || date.sunday?)
    ].compact.join(" ")
  end

  def calendar_item_classes(task)
    [
      "calendar-item",
      "calendar-item--#{task.status.dasherize}",
      ("calendar-item--overdue" if task.overdue?)
    ].compact.join(" ")
  end

  # "14:00" (or "09:00–10:30" when the task has both dates on the same day).
  def calendar_task_time(task)
    main = Calendar::Agenda.time_of(task).in_time_zone
    if task.starts_at.present? && task.due_at.present? && task.starts_at.in_time_zone.to_date == task.due_at.in_time_zone.to_date &&
       task.starts_at != task.due_at
      "#{task.starts_at.in_time_zone.strftime("%H:%M")}–#{task.due_at.in_time_zone.strftime("%H:%M")}"
    else
      main.strftime("%H:%M")
    end
  end

  # "Dia todo", "20:00" or "20:00–22:00"; on the later days of a multi-day event, "até 18:00".
  def calendar_event_time(event, date)
    return "Dia todo" if event.all_day?
    starts = event.starts_at.in_time_zone
    ends = event.ends_at&.in_time_zone
    return "até #{ends.strftime("%H:%M")}" if ends && date > event.first_day && date == event.last_day
    return "Dia todo" if date > event.first_day
    ends && ends.to_date == starts.to_date && ends != starts ? "#{starts.strftime("%H:%M")}–#{ends.strftime("%H:%M")}" : starts.strftime("%H:%M")
  end

  def calendar_task_label(task)
    kind = task.due_at.present? ? "prazo" : "início"
    "#{task.title} — #{kind} às #{Calendar::Agenda.time_of(task).in_time_zone.strftime("%H:%M")}, " \
      "#{BadgesHelper::STATUS_LABELS.fetch(task.status, task.status).downcase}"
  end

  def calendar_last_synced(connection)
    return "Ainda não sincronizou" if connection&.last_synced_at.blank?
    "Há #{time_ago_in_words(connection.last_synced_at)}"
  end

  private
    def calendar_sync_state(task, event, connection)
      if !connection.active?
        [ "error", "Google: ligação com erro", connection.last_error ]
      elsif !task.calendar_eligible?
        [ "pending", "Google: sem data", "Define uma data de início ou prazo para sincronizar." ]
      elsif event.nil?
        [ "pending", CALENDAR_SYNC_LABELS["pending"], nil ]
      elsif event.sync_error?
        [ "error", event.conflict? ? "Google: conflito" : CALENDAR_SYNC_LABELS["error"], event.last_error ]
      elsif event.sync_synced? && event.last_synced_at && task.updated_at > event.last_synced_at
        [ "pending", CALENDAR_SYNC_LABELS["pending"], nil ]
      else
        state = event.sync_status
        title = event.last_synced_at ? "Sincronizada há #{time_ago_in_words(event.last_synced_at)}" : nil
        [ state, CALENDAR_SYNC_LABELS[state], title ]
      end
    end
end
