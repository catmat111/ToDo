module Calendar
  # The range shown by the calendar page: a Monday-first month grid
  # (?month=YYYY-MM) or a single week (?view=week&date=YYYY-MM-DD).
  # Invalid or missing params fall back to "today" in the user's zone.
  class Period
    VIEWS = %w[month week].freeze
    MONTH_NAMES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze
    WEEKDAY_NAMES = %w[Seg Ter Qua Qui Sex Sáb Dom].freeze
    WEEKDAY_FULL_NAMES = %w[segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado domingo].freeze

    attr_reader :view, :anchor, :today

    def self.from_params(params, today: Time.zone.today)
      view = VIEWS.include?(params[:view].to_s) ? params[:view].to_s : "month"
      anchor = if view == "week"
        parse_date(params[:date]) || today
      else
        parse_month(params[:month]) || parse_date(params[:date])&.beginning_of_month || today.beginning_of_month
      end
      new(view: view, anchor: anchor, today: today)
    end

    def self.parse_month(value)
      match = value.to_s.match(/\A(\d{4})-(\d{2})\z/)
      match && Date.new(match[1].to_i, match[2].to_i, 1)
    rescue Date::Error
      nil
    end

    def self.parse_date(value)
      return nil unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def initialize(view:, anchor:, today:)
      @view = view
      @anchor = anchor
      @today = today
    end

    def month?
      view == "month"
    end

    def week?
      view == "week"
    end

    def first_day
      month? ? anchor.beginning_of_month.beginning_of_week(:monday) : anchor.beginning_of_week(:monday)
    end

    def last_day
      month? ? anchor.end_of_month.end_of_week(:monday) : anchor.end_of_week(:monday)
    end

    def days
      (first_day..last_day).to_a
    end

    def weeks
      days.each_slice(7).to_a
    end

    # Time range in the current zone covering every visible day.
    def time_range
      first_day.in_time_zone.beginning_of_day..last_day.in_time_zone.end_of_day
    end

    def in_focus?(date)
      month? ? date.month == anchor.month && date.year == anchor.year : true
    end

    def today?(date)
      date == today
    end

    def title
      if month?
        "#{MONTH_NAMES[anchor.month - 1].capitalize} de #{anchor.year}"
      else
        week_title
      end
    end

    def previous_params
      month? ? { month: (anchor << 1).strftime("%Y-%m") } : { view: "week", date: (anchor - 7).iso8601 }
    end

    def next_params
      month? ? { month: (anchor >> 1).strftime("%Y-%m") } : { view: "week", date: (anchor + 7).iso8601 }
    end

    def today_params
      month? ? {} : { view: "week" }
    end

    def contains_today?
      (first_day..last_day).cover?(today) && in_focus?(today)
    end

    # Links used by the Mês/Semana tabs keep the user roughly in the same place.
    def month_params
      { month: anchor.strftime("%Y-%m") }
    end

    def week_params
      date = month? ? (in_focus?(today) ? today : anchor.beginning_of_month) : anchor
      { view: "week", date: date.iso8601 }
    end

    private
      def week_title
        from = first_day
        to = last_day
        if from.month == to.month
          "#{from.day} – #{to.day} de #{MONTH_NAMES[to.month - 1]} de #{to.year}"
        elsif from.year == to.year
          "#{from.day} de #{MONTH_NAMES[from.month - 1]} – #{to.day} de #{MONTH_NAMES[to.month - 1]} de #{to.year}"
        else
          "#{from.day} de #{MONTH_NAMES[from.month - 1]} de #{from.year} – #{to.day} de #{MONTH_NAMES[to.month - 1]} de #{to.year}"
        end
      end
  end
end
