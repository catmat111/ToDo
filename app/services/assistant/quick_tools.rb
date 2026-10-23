module Assistant
  # What the assistant may do from the general chat: add tasks and events for the user.
  # The model splits the sentence and names each thing; the date is read by the app from
  # the part of the user's own sentence that thing came from (small models drop dates).
  class QuickTools < Tools
    DEFINITIONS = [
      function("criar_tarefa", "Cria uma tarefa (algo a fazer). Sem data, fica para hoje.",
               { titulo: { type: "string", description: "O que fazer, curto, começando por um verbo (ex.: «Ligar ao banco»), sem a data" },
                 quando: { type: "string", description: "#{Dates::HINT}. Vazio se não disse." } }, %i[titulo]),
      function("criar_evento", "Marca um evento no calendário (algo que acontece a uma hora: jantar, reunião, aula, consulta).",
               { titulo: { type: "string", description: "O evento, curto, sem a data (ex.: «Jantar com a Ana»)" },
                 quando: { type: "string", description: Dates::HINT },
                 local: { type: "string", description: "Onde, se disse" } }, %i[titulo quando])
    ].freeze

    attr_reader :records

    def initialize(user, message = "")
      super()
      @user = user
      @records = []
      @clauses = message.to_s.split(/\s*(?:[,;\n]|\s+e\s+)\s*/i).compact_blank
    end

    private
      def tool_criar_tarefa(args)
        title = args["titulo"].to_s.squish.presence or return "Erro: falta o título."
        time, has_hour = date_for(title, args["quando"])
        due = time ? (has_hour ? time : time.end_of_day) : Time.zone.now.end_of_day
        result = Tasks::Create.call(user: @user, params: { title: title.upcase_first, due_at: due })
        return "Erro: #{result.error}" unless result.success?
        @records << result.task
        done("Adicionei a tarefa «#{result.task.title}» para #{when_text(due)}.")
      end

      def tool_criar_evento(args)
        title = args["titulo"].to_s.squish.presence or return "Erro: falta o título."
        time, has_hour = date_for(title, args["quando"])
        return "Erro: não percebi quando é «#{title}». Diz o dia (e a hora)." unless time
        event = @user.events.new(title: title.upcase_first, location: args["local"].presence, all_day: !has_hour,
                                 starts_at: time, ends_at: (time + 1.hour if has_hour))
        return "Erro: #{event.errors.full_messages.to_sentence}" unless event.save
        AuditLog.record("event.created", resource: event, user: @user, title: event.title)
        @records << event
        done("Marquei o evento «#{event.title}» para #{has_hour ? Dates.format(time) : I18n.l(time.to_date, format: "%d/%m/%Y")}.")
      end

      # The date in the user's own words for this thing, else what the model passed.
      def date_for(title, quando)
        words = Tasks::Chat.normalize(title).scan(/\p{L}{3,}/)
        clause = @clauses.max_by { |c| (Tasks::Chat.normalize(c).scan(/\p{L}{3,}/) & words).size }
        if clause && (words & Tasks::Chat.normalize(clause).scan(/\p{L}{3,}/)).any?
          _, found = Tasks::Chat::When.extract(clause)
          return [ found.time, found.has_time ] if found
        end
        quando.present? ? Dates.parse(quando) : nil
      end

      def when_text(time)
        return "hoje" if time.to_date == Time.zone.today && time == time.end_of_day
        time == time.end_of_day ? I18n.l(time.to_date, format: "%d/%m/%Y") : Dates.format(time)
      end
  end
end
