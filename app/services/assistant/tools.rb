module Assistant
  # Base for a set of tools the assistant may call. Subclasses list DEFINITIONS (Ollama
  # function schemas) and implement one private tool_<name>(args) per tool, returning a
  # short text for the model. Bad input becomes an error text, never an exception.
  class Tools
    def self.function(name, description, properties = {}, required = properties.keys)
      { type: "function", function: { name: name, description: description,
                                       parameters: { type: "object", properties: properties, required: required.map(&:to_s) } } }
    end

    attr_reader :changed

    def initialize
      @changed = false
    end

    def definitions = self.class::DEFINITIONS

    def call(name, args)
      args = args.is_a?(Hash) ? args.stringify_keys : {}
      name = repaired_name(name, args)
      Rails.logger.info("[assistant] #{self.class.name.demodulize}: #{name} #{args.to_json}")
      method = "tool_#{name}"
      return "Erro: ferramenta desconhecida «#{name}»." unless respond_to?(method, true)
      send(method, args)
    rescue ActiveRecord::RecordInvalid, ArgumentError, TypeError => e
      "Erro: #{e.message.truncate(200)}"
    end

    private
      def done(text)
        @changed = true
        text
      end

      # Small models sometimes send one tool's arguments under another tool's name (e.g.
      # tag names to mudar_prioridade). When the arguments only fit another tool, use that one.
      def repaired_name(name, args)
        return name if args.empty?
        fits = ->(definition) { (args.keys - definition.dig(:function, :parameters, :properties).keys.map(&:to_s)).empty? }
        current = definitions.find { |d| d.dig(:function, :name) == name }
        return name if current.nil? || fits.(current)
        definitions.find(&fits)&.dig(:function, :name) || name
      end
  end
end
