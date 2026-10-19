module Tasks
  class Chat
    # Reads a date/time out of a short Portuguese phrase, in the current Time.zone.
    #
    #   When.parse("amanhã às 9h")       # => #<When time: tomorrow 09:00, has_time: true>
    #   When.parse("sexta")              # => #<When time: next Friday 00:00, has_time: false>
    #   When.parse("daqui a 2 horas")    # => #<When time: now + 2h, has_time: true>
    #   When.before_due("1 dia antes", due) # => due - 1 day
    #
    #   When.extract("Ligar ao banco amanhã às 10h") # => ["Ligar ao banco", #<When tomorrow 10:00>]
    #
    # parse/before_due expect text already normalized (lower case, no accents; see Chat.normalize).
    class When < Data.define(:time, :has_time)
      WEEKDAYS = { "domingo" => 0, "segunda" => 1, "terca" => 2, "quarta" => 3, "quinta" => 4, "sexta" => 5, "sabado" => 6 }.freeze
      MONTHS = %w[janeiro fevereiro marco abril maio junho julho agosto setembro outubro novembro dezembro].freeze
      NUMBERS = { "um" => 1, "uma" => 1, "dois" => 2, "duas" => 2, "tres" => 3, "quatro" => 4, "cinco" => 5,
                  "seis" => 6, "sete" => 7, "oito" => 8, "nove" => 9, "dez" => 10 }.freeze
      UNITS = { /\Amin/ => :minutes, /\Ah/ => :hours, /\Adia/ => :days, /\Asemana/ => :weeks }.freeze
      AMOUNT = "(\\d+|#{NUMBERS.keys.join("|")}|meia)"
      UNIT = "(minutos?|mins?|horas?|h|dias?|semanas?)"
      PERIODS = { "de manha" => 9, "a tarde" => 15, "ao fim da tarde" => 18, "a noite" => 20, "meio-dia" => 12, "meio dia" => 12 }.freeze

      def self.parse(text, now: Time.zone.now)
        text = text.to_s
        if (match = text.match(/\b(?:em|daqui a|dentro de)\s+#{AMOUNT}\s*#{UNIT}\b/))
          return new(time: now + duration(match[1], match[2]), has_time: true)
        end

        date = date_in(text, now)
        hour, minute = time_in(text)
        return nil if date.nil? && hour.nil?

        if date.nil?
          time = now.change(hour: hour, min: minute)
          time += 1.day if time <= now
          return new(time: time, has_time: true)
        end
        return new(time: date.in_time_zone.change(hour: hour, min: minute), has_time: true) if hour
        new(time: date.in_time_zone, has_time: false)
      end

      # "1 dia antes", "15 min antes", "na vespera", "no prazo" — relative to +due+.
      def self.before_due(text, due)
        return nil if due.nil?
        return due if text.match?(/\b(no prazo|na hora|a hora do prazo)\b/)
        return due - 1.day if text.match?(/\bna vespera\b/)
        match = text.match(/\b#{AMOUNT}\s*#{UNIT}\s+antes\b/)
        match && due - duration(match[1], match[2])
      end

      # Date words that can be cut out of a sentence (with the little word before them).
      def self.phrase_patterns
        weekdays = WEEKDAYS.keys.join("|")
        [
          /\s*,?\s*\b(?:em|daqui a|dentro de)\s+#{AMOUNT}\s*#{UNIT}\b/,
          /\s*,?\s*\b(?:para\s+|ate\s+)?(?:depois de amanha|amanha|hoje)\b/,
          /\s*,?\s*\b(?:na\s+|no\s+|para\s+|ate\s+|esta\s+|este\s+)?(?:proxim[ao]\s+)?(?:#{weekdays})(?:-feira)?\b/,
          %r{\s*,?\s*\b(?:no dia\s+|dia\s+|a\s+|em\s+|para\s+|ate\s+)?\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?\b},
          /\s*,?\s*\b(?:no dia\s+|dia\s+|a\s+|em\s+|para\s+|ate\s+)?\d{1,2}\s+de\s+(?:#{MONTHS.join("|")})\b/,
          /\s*,?\s*\b(?:no\s+|para\s+|ate\s+)?dia\s+\d{1,2}\b/,
          /\s*\b(?:as|pelas|a)?\s*\d{1,2}\s*(?:h|:)\s*(?:\d{2})?\b/,
          /\s*\b(?:as|pelas)\s+\d{1,2}\b(?!\s*(?:[\/-]|de\b|dias?\b|horas?\b|min|semanas?\b))/,
          /\s*\b(?:#{PERIODS.keys.map { |p| Regexp.escape(p) }.join("|")}|ao meio-dia|meia-noite|meia noite)\b/
        ]
      end

      # Splits a sentence the user typed into what to do and when.
      # Returns [text without the date words, When or nil]; keeps the text whole when it
      # would be left empty.
      def self.extract(raw, now: Time.zone.now)
        normalized = Chat.normalize(raw)
        cut = normalized.dup
        phrase_patterns.each do |pattern|
          cut.gsub!(pattern) { |found| "\0" * found.length }
        end
        removed = cut.each_char.each_with_index.select { |char, _| char == "\0" }.map(&:last)
        return [ raw.squish, nil ] if removed.empty?

        found = parse(normalized, now: now)
        rest = raw.each_char.each_with_index.reject { |_, i| removed.include?(i) }.map(&:first).join
        rest = rest.squish.sub(/[\s,;:–-]+\z/, "").sub(/\s+(?:para|até|ate|no|na|em|a|às|as|de|do|da)\z/i, "")
        rest.present? && found ? [ rest, found ] : [ raw.squish, found ]
      end

      def self.duration(amount, unit)
        return 30.minutes if amount == "meia"
        count = NUMBERS.fetch(amount) { amount.to_i }
        count.public_send(UNITS.find { |pattern, _| unit.match?(pattern) }.last)
      end

      def self.date_in(text, now)
        today = now.to_date
        return today + 2 if text.match?(/\bdepois de amanha\b/)
        return today + 1 if text.match?(/\bamanha\b/)
        return today if text.match?(/\bhoje\b/)

        if (match = text.match(/\b(#{WEEKDAYS.keys.join("|")})(?:-feira)?\b/))
          ahead = (WEEKDAYS[match[1]] - today.wday) % 7
          return today + (ahead.zero? ? 7 : ahead)
        end
        if (match = text.match(%r{\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b}))
          return build_date(today, match[1].to_i, match[2].to_i, match[3])
        end
        if (match = text.match(/\b(\d{1,2})\s+de\s+(#{MONTHS.join("|")})\b/))
          return build_date(today, match[1].to_i, MONTHS.index(match[2]) + 1, nil)
        end
        if (match = text.match(/\bdia\s+(\d{1,2})\b/))
          day = match[1].to_i
          date = Date.new(today.year, today.month, day) rescue nil
          return date && date < today ? today.next_month.change(day: day) : date
        end
        nil
      end

      # The given day/month, this year or the next one if it has already passed.
      def self.build_date(today, day, month, year)
        date = Date.new(year ? (year.to_i % 100 == year.to_i ? 2000 + year.to_i : year.to_i) : today.year, month, day)
        year.nil? && date < today ? date.next_year : date
      rescue Date::Error
        nil
      end

      def self.time_in(text)
        if (match = text.match(/\b(\d{1,2})\s*(?:h|:)\s*(\d{2})?\b/)) ||
           (match = text.match(/\b(?:as|pelas|a)\s+(\d{1,2})\b(?!\s*(?:[\/-]|de\b|dias?\b|horas?\b|min|semanas?\b))/))
          hour = match[1].to_i
          minute = match[2].to_i
          return [ hour, minute ] if hour < 24 && minute < 60
        end
        PERIODS.each { |phrase, hour| return [ hour, 0 ] if text.include?(phrase) }
        return [ 0, 0 ] if text.include?("meia-noite") || text.include?("meia noite")
        nil
      end

      private_class_method :duration, :date_in, :build_date, :time_in
    end
  end
end
