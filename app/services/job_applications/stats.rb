module JobApplications
  # Numbers for the "Estatísticas" page: funnel, response rate, time to first answer,
  # applications per month and per source. Stages are reached via the status OR the
  # history (an application now "rejected" may have had an interview first).
  class Stats
    RESPONSE_EVENTS = %w[interview offer rejected].freeze
    SILENT_AFTER = 14.days
    MONTHS = 6

    attr_reader :user

    def initialize(user, now: Time.current)
      @user = user
      @now = now
      @applications = user.job_applications.includes(:job_listing, :job_application_events).to_a
    end

    def total = @applications.size

    def any? = total.positive?

    # [[label, count, percent_of_first], …]
    def funnel
      stages = [
        [ "Guardadas", @applications.size ],
        [ "Enviadas", sent.size ],
        [ "Entrevistas", @applications.count { |a| reached?(a, "interview") || reached?(a, "offer") } ],
        [ "Ofertas", @applications.count { |a| reached?(a, "offer") } ]
      ]
      base = [ stages.first.last, 1 ].max
      stages.map { |label, count| [ label, count, (count * 100.0 / base).round ] }
    end

    def sent_count = sent.size
    def interviews_count = funnel[2][1]
    def offers_count = funnel[3][1]

    # % of sent applications that got any answer (interview, offer or rejection).
    def response_rate
      return nil if sent.empty?
      (answered.size * 100.0 / sent.size).round
    end

    # Average days from sending to the first answer.
    def average_days_to_response
      days = answered.filter_map { |a| days_to_first_answer(a) }
      days.empty? ? nil : (days.sum / days.size).round
    end

    # Sent, no answer and older than SILENT_AFTER — candidates for a follow-up.
    def silent
      sent.select { |a| a.applied? && first_answer(a).nil? && a.applied_at && a.applied_at < @now - SILENT_AFTER }
          .sort_by(&:applied_at)
    end

    # Current status of every application that left "saved", in the donut's slot order
    # (validated palette order: no two easily-confused colours are neighbours).
    # [[status, label, count, percent], …]
    DONUT_ORDER = {
      "applied" => "À espera de resposta", "rejected" => "Rejeitada", "interview" => "Entrevista",
      "offer" => "Oferta", "withdrawn" => "Desisti"
    }.freeze

    def status_breakdown
      counts = @applications.reject(&:saved?).group_by(&:status).transform_values(&:size)
      total = counts.values.sum
      DONUT_ORDER.map do |status, label|
        count = counts.fetch(status, 0)
        [ status, label, count, total.zero? ? 0 : (count * 100.0 / total).round ]
      end
    end

    # [["out 2026", 4], …] for the last MONTHS months, by date sent (or created).
    def per_month
      start = (@now.to_date << (MONTHS - 1)).beginning_of_month
      counts = @applications.group_by { |a| (a.applied_at || a.created_at).to_date.beginning_of_month }
      (0...MONTHS).map do |i|
        month = start >> i
        [ I18n.l(month, format: "%b %Y"), counts.fetch(month, []).size ]
      end
    end

    # [["LinkedIn", 12], ["Manual", 3], …], biggest first.
    def per_source
      @applications.group_by { |a| a.job_listing ? JobSearch.source_label(a.job_listing.source) : "Manual" }
                   .map { |label, list| [ label, list.size ] }
                   .sort_by { |_, count| -count }
    end

    private
      def sent
        @sent ||= @applications.select { |a| a.applied_at.present? || !a.saved? && !a.withdrawn? }
      end

      def answered
        @answered ||= sent.select { |a| first_answer(a) || a.interview? || a.offer? || a.rejected? }
      end

      def reached?(application, stage)
        application.status == stage || application.job_application_events.any? { |e| e.event_type == stage }
      end

      def first_answer(application)
        application.job_application_events.select { |e| RESPONSE_EVENTS.include?(e.event_type) }.min_by(&:occurred_at)
      end

      def days_to_first_answer(application)
        answer = first_answer(application)
        return nil unless answer && application.applied_at && answer.occurred_at >= application.applied_at
        ((answer.occurred_at - application.applied_at) / 1.day)
      end
  end
end
