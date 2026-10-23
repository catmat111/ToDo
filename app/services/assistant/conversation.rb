module Assistant
  # One request to the local LLM with tools: ask, run the tools it calls, feed back the
  # results, until it answers in text (at most MAX_ROUNDS).
  #
  # What happened is told by the tools' own results — a small model's summary can be
  # wrong. Its text is used only when no tool ran (a question, an explanation).
  class Conversation
    Reply = Data.define(:text, :changed) do
      def changed? = changed
    end

    MAX_ROUNDS = 5
    WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze

    def self.today
      now = Time.zone.now
      "Hoje é #{WEEKDAYS[now.wday]}, #{now.to_date.iso8601}, #{now.strftime("%H:%M")}."
    end

    def initialize(client:, tools:, system:, fallback:)
      @client = client
      @tools = tools
      @system = system
      @fallback = fallback
    end

    def run(message)
      messages = [ { role: "system", content: @system }, { role: "user", content: message.to_s.strip } ]
      results = []
      done = []

      MAX_ROUNDS.times do
        reply = @client.chat(messages: messages, tools: @tools.definitions)
        messages << reply.slice("role", "content", "tool_calls")
        calls = Array(reply["tool_calls"])
        return finish(reply["content"], results) if calls.empty?

        calls.each do |call|
          function = call["function"] || {}
          name = function["name"].to_s
          arguments = parse_arguments(function["arguments"])
          # Small models sometimes repeat a call they already made; run each one once.
          result = if done.include?([ name, arguments ])
            "Já feito antes; não repitas."
          else
            done << [ name, arguments ]
            @tools.call(name, arguments).tap { |text| results << [ name, arguments, text ] }
          end
          messages << { role: "tool", tool_name: name, content: result }
        end
      end
      finish(nil, results)
    end

    private
      def finish(text, results)
        # A retry of the same tool that worked hides its earlier error.
        shown = results.reject { |name, _, out| out.start_with?("Erro") && results.any? { |n, _, o| n == name && !o.start_with?("Erro") } }
        text = shown.any? ? shown.map(&:last).uniq.join(" ") : text.to_s.strip
        Reply.new(text: (text.presence || @fallback).truncate(800), changed: @tools.changed)
      end

      def parse_arguments(arguments)
        arguments.is_a?(String) ? JSON.parse(arguments) : arguments
      rescue JSON::ParserError
        {}
      end
  end
end
