module Assistant
  # Dates the assistant passes to its tools. Small models get weekdays wrong, so they copy
  # the user's words and the app's own Portuguese parser (Tasks::Chat::When) does the maths.
  module Dates
    HINT = "Copia as palavras do utilizador sobre a data, sem fazer contas (ex.: «amanhã às 9h», «sexta às 15h», «20/11», «1 dia antes», «na véspera»)".freeze

    # An ISO date, or words like "sexta às 15h" / "na véspera às 10h" (the latter relative
    # to +due_at+). Returns [time, has_hour] or nil.
    def self.parse(value, due_at: nil)
      raw = value.to_s.strip
      if raw.match?(/\A\d{4}-\d{2}-\d{2}/) # ISO
        time = Time.zone.parse(raw) or return nil
        return [ time, raw.include?("T") ]
      end
      text = Tasks::Chat.normalize(raw)
      return nil if text.blank?
      if due_at && (time = Tasks::Chat::When.before_due(text, due_at))
        # "na véspera às 10h": the day comes from the due date, the hour from the words
        at = Tasks::Chat::When.parse(text.sub(/\b(?:na vespera|no prazo|antes)\b.*?(?=\b(?:as|pelas)\b|\d|\z)/, ""))
        time = time.change(hour: at.time.hour, min: at.time.min) if at&.has_time && text.match?(/vespera/)
        return [ time, true ]
      end
      found = Tasks::Chat::When.parse(text)
      found && [ found.time, found.has_time ]
    rescue ArgumentError
      nil
    end

    def self.format(time) = I18n.l(time, format: "%d/%m/%Y %H:%M")
  end
end
