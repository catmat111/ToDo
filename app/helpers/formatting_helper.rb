# Dates as people read them, in the signed-in user's time zone.
module FormattingHelper
  def format_datetime(time, format: :short)
    return "—" if time.blank?
    all_day?(time) ? l(time.in_time_zone.to_date, format: :long) : l(time.in_time_zone, format: format)
  end

  def format_date(date, format: :default)
    date.present? ? l(date.to_date, format: format) : "—"
  end

  # "hoje às 14:00", "amanhã", "há 3 dias"… for due dates.
  # A deadline at 23:59 means "some time that day" (no specific hour) — e.g. tasks
  # added from the quick-add post-it. Such dates are shown without a time.
  def all_day?(time)
    time.present? && time.in_time_zone.strftime("%H:%M") == "23:59"
  end

  def relative_due(time)
    return "sem prazo" if time.blank?
    t = time.in_time_zone
    today = Time.zone.today
    hour = all_day?(t) ? "" : " às #{l(t, format: '%H:%M')}"
    case t.to_date
    when today then "hoje#{hour}"
    when today + 1 then "amanhã#{hour}"
    when today - 1 then "ontem"
    else
      return l(t.to_date, format: "%-d %b") if all_day?(t)
      t.future? ? "em #{time_ago_in_words(t)}" : "há #{time_ago_in_words(t)}"
    end
  end
end
