module Tasks
  # The post-it chat on a task page: short Portuguese commands that change that task.
  # Rule based, like Inbox::Classifier — no outside service. Every change goes through
  # the same services/models as the buttons, so validations and audit behave the same.
  #
  #   reply = Tasks::Chat.call(task, "lembra-me amanhã às 9h")
  #   reply.ok?      # => true
  #   reply.text     # => "Vou lembrar-te a 14/10 às 09:00."
  #   reply.changed? # => true (the page should be refreshed)
  class Chat
    Reply = Data.define(:ok, :text, :changed, :link) do
      def ok? = ok
      def changed? = changed
    end

    EXAMPLES = [
      "subtarefa rever capítulo 3",
      "lembra-me amanhã às 9h",
      "prazo sexta às 18h",
      "etiqueta faculdade",
      "prioridade alta",
      "partilhar com ana@exemplo.pt",
      "repetir todas as semanas",
      "concluir"
    ].freeze

    PRIORITY_WORDS = { "baixa" => 0, "normal" => 1, "media" => 1, "alta" => 2, "urgente" => 3 }.freeze
    FREQUENCY_WORDS = { /\bdia|diari/ => "daily", /\bsemana/ => "weekly", /\bmes|\bmeses|mensal/ => "monthly", /\bano|anual/ => "yearly" }.freeze

    # Lower case without accents, keeping every character in place so a match on the
    # normalized text can cut the same slice out of what the user typed.
    def self.normalize(text)
      text.to_s.each_char.map do |char|
        plain = I18n.transliterate(char.downcase)
        plain.length == 1 ? plain : char.downcase
      end.join
    end

    def self.call(...)
      new(...).call
    end

    def initialize(task, message)
      @task = task
      @user = task.user
      @raw = message.to_s.strip
      @text = self.class.normalize(@raw)
    end

    def call
      return help if @text.blank? || @text.match?(/\A(ajuda|help|\?|o que (posso|consigo|sabes) fazer)/)

      status_command || new_task || subtasks || reminder || remove_tags || tags || due || start_date ||
        priority || rename || description || share || link || recurrence || dependency || not_understood
    end

    private
      attr_reader :task, :user, :text

      # Text the user typed after a normalized-text match, with its accents and capitals.
      def original(match, group = 1)
        @raw[match.begin(group)...match.end(group)].strip
      end

      def ok(message, link: nil) = Reply.new(ok: true, text: message, changed: true, link: link)
      def failure(message) = Reply.new(ok: false, text: message, changed: false, link: nil)

      def help
        Reply.new(ok: true, changed: false, link: nil,
                  text: "Posso mudar esta tarefa por ti. Experimenta, por exemplo: #{EXAMPLES.map { |e| "«#{e}»" }.join(", ")}.")
      end

      def not_understood
        failure("Não percebi. Experimenta: #{EXAMPLES.first(4).map { |e| "«#{e}»" }.join(", ")} — ou escreve «ajuda».")
      end

      def at(time)
        I18n.l(time, format: "%d/%m às %H:%M")
      end

      def on(time, all_day)
        all_day ? I18n.l(time.to_date, format: "%d/%m") : at(time)
      end

      # --- Estado ---------------------------------------------------------------
      def status_command
        case text
        when /\A(concluir|conclui|concluida|feito|feita|terminei|acabei|marca(r)? como (concluida|feita))\b/
          result = Complete.call(task)
          return failure(result.error) unless result.success?
          next_due = result.next_task&.due_at
          ok("Tarefa concluída. 🎉#{" A próxima fica para #{at(next_due)}." if next_due}")
        when /\A(iniciar|inicia|comecar|comeca agora|comecei|em curso)\z/
          change_status("in_progress", "Marquei como em curso.")
        when /\A(cancelar|cancela)( (a|esta) tarefa)?\z/
          change_status("cancelled", "Tarefa cancelada.")
        when /\A(reabrir|reabre)\b/
          change_status("pending", "Tarefa reaberta.")
        when /\A(desarquivar|restaurar)\b/
          archive(false, "Tarefa restaurada do arquivo.")
        when /\Aarquiva(r)?\b/
          archive(true, "Tarefa arquivada.")
        when /\A(eliminar|elimina|apagar|apaga)( (a|esta) tarefa)?\z/
          failure("Para eliminar, usa o botão «⋯» no topo da página — assim pedimos confirmação.")
        end
      end

      def change_status(to, message)
        result = ChangeStatus.call(task, to: to)
        result.success? ? ok(message) : failure(result.error)
      end

      def archive(archived, message)
        result = Archive.call(task, archived: archived)
        result.success? ? ok(message) : failure(result.error)
      end

      # --- Nova tarefa para hoje (o que o chat fazia antes) ---------------------
      def new_task
        match = text.match(/\A(?:nova tarefa|tarefa para hoje|outra tarefa|novo evento|evento)\s*:?\s+(.+)/m) or return
        added = QuickAdd.call(user, match[0].start_with?("novo evento", "evento") ? @raw : original(match))
        return failure(added.text) unless added.ok?
        record = added.record
        what = record.is_a?(Event) ? "o evento" : "a tarefa"
        Reply.new(ok: true, changed: false, link: (record if record.is_a?(Task)), text: "Adicionei #{what} «#{record.title}».")
      end

      # --- Subtarefas -----------------------------------------------------------
      def subtasks
        match = text.match(/\A(?:(?:adiciona|adicionar|cria|criar|nova|novo)\s+(?:uma\s+|um\s+)?)?(?:subtarefas?|passos?)\s*:?\s+(.+)/m) or return
        return failure("Esta tarefa já está no nível máximo de subtarefas.") if task.ancestors.size + 1 >= Task::MAX_DEPTH

        titles = original(match).split(/\s*[;\n]\s*|\s*,\s*/).map(&:strip).compact_blank
        created = titles.filter_map do |title|
          result = Create.call(user: user, params: { title: title, parent_task_id: task.id, task_type: task.task_type })
          result.task if result.success?
        end
        return failure("Não consegui criar a subtarefa.") if created.empty?
        names = created.map { |t| "«#{t.title}»" }.to_sentence(two_words_connector: " e ", last_word_connector: " e ")
        ok(created.one? ? "Adicionei a subtarefa #{names}." : "Adicionei #{created.size} subtarefas: #{names}.")
      end

      # --- Lembretes ------------------------------------------------------------
      def reminder
        match = text.match(/\A(?:lembra-me|lembra me|lembrar-me|lembrar|lembra|lembrete|avisa-me|avisa me|avisa)\b\s*(.*)/m) or return
        rest = match[1]
        return failure("Esta tarefa já não está aberta, por isso não recebe lembretes.") unless task.open?

        time = When.before_due(rest, task.due_at)
        if time.nil? && rest.match?(/\bantes\b|\bvespera\b|\bno prazo\b/)
          return failure("Esta tarefa não tem prazo. Define um primeiro, por exemplo «prazo sexta às 18h».")
        end
        if time.nil? && (parsed = When.parse(rest))
          time = parsed.has_time ? parsed.time : parsed.time.change(hour: 9)
        end
        return failure("Quando? Por exemplo: «lembra-me amanhã às 9h», «lembra-me daqui a 2 horas» ou «lembra-me 1 dia antes».") unless time

        channel = rest.match?(/\bpor (e-?mail|mail)\b/) ? "email" : "in_app"
        reminder = task.reminders.build(remind_at: time, channel: channel)
        return failure("Não consegui criar o lembrete: #{reminder.errors.full_messages.to_sentence.downcase_first}.") unless reminder.save
        AuditLog.record("reminder.created", resource: reminder, user: user, task_id: task.id, channel: channel)
        ok("Vou lembrar-te a #{at(time)}#{" por email" if channel == "email"}.")
      rescue ActiveRecord::RecordNotUnique
        failure("Já tens um lembrete para esse momento.")
      end

      # --- Etiquetas ------------------------------------------------------------
      def remove_tags
        match = text.match(/\A(?:tira|tirar|remove|remover|apaga|apagar)\s+(?:a\s+|as\s+)?(?:etiquetas?|tags?)\s*:?\s+(.+)/) or return
        names = tag_names(original(match)).map(&:downcase)
        removed = task.tags.select { |tag| names.include?(tag.name.downcase) }
        return failure("Esta tarefa não tem essa etiqueta.") if removed.empty?
        task.tags.delete(*removed)
        AuditLog.record("task.updated", resource: task, user: user, fields: [ "tags" ])
        ok("Tirei #{quoted(removed.map(&:name))}.")
      end

      def tags
        match = text.match(/\A(?:(?:adiciona|adicionar|poe|por|mete)\s+(?:a\s+|as\s+)?)?(?:etiquetas?|tags?)\s*:?\s+(.+)/) or return
        added = tag_names(original(match)).filter_map do |name|
          tag = user.tags.where("LOWER(name) = ?", name.downcase).first || user.tags.create(name: name)
          next unless tag.persisted?
          AuditLog.record("tag.created", resource: tag, user: user, name: tag.name) if tag.previously_new_record?
          next if task.tags.include?(tag)
          task.tags << tag
          tag
        end
        return failure("Essa etiqueta já está nesta tarefa.") if added.empty?
        AuditLog.record("task.updated", resource: task, user: user, fields: [ "tags" ])
        ok("Etiqueta#{"s" if added.many?} #{quoted(added.map(&:name))} adicionada#{"s" if added.many?}.")
      end

      def tag_names(list)
        list.split(/\s*[,;]\s*|\s+e\s+/).map { |name| name.delete_prefix("#").squish.truncate(40, omission: "") }.compact_blank.uniq
      end

      def quoted(names)
        names.map { |n| "«#{n}»" }.to_sentence(two_words_connector: " e ", last_word_connector: " e ")
      end

      # --- Datas ----------------------------------------------------------------
      def due
        if text.match?(/\A(sem prazo|tira(r)? (o )?prazo|remove(r)? (o )?prazo)\b/)
          return update({ due_at: nil }, "Tirei o prazo.")
        end
        match = text.match(/\A(?:(?:muda|mudar|altera|alterar|passa|passar)\s+(?:o\s+)?)?(?:prazo|entrega|para entregar)\s*(?:para|:|a)?\s*(.+)/) or return
        parsed = When.parse(match[1]) or return failure("Não percebi a data. Experimenta «prazo amanhã», «prazo sexta às 18h» ou «prazo 20/10».")
        time = parsed.has_time ? parsed.time : parsed.time.end_of_day
        update({ due_at: time }, "Prazo mudado para #{on(time, !parsed.has_time)}.")
      end

      def start_date
        match = text.match(/\A(?:inicio|comeca|comecar|comeca a|comeca em)\s*(?:a|em|:)?\s*(.+)/) or return
        parsed = When.parse(match[1]) or return
        time = parsed.has_time ? parsed.time : parsed.time.change(hour: 9)
        update({ starts_at: time }, "Começa a #{at(time)}.")
      end

      # --- Prioridade, título, descrição -----------------------------------------
      def priority
        match = text.match(/\A(?:prioridade\s*:?\s*)?(baixa|normal|media|alta|urgente)(?:\s+prioridade)?\z/) ||
                text.match(/\Aprioridade\s*:?\s*(baixa|normal|media|alta|urgente)\b/)
        if match.nil?
          return update({ priority: 3 }, "Prioridade: Urgente.") if text.match?(/\A(e |isto e |marca(r)? como )?urgente\z/)
          return update({ priority: 2 }, "Prioridade: Alta.") if text.match?(/\A(e |isto e |marca(r)? como )?importante\z/)
          return
        end
        value = PRIORITY_WORDS.fetch(match[1])
        update({ priority: value }, "Prioridade: #{Task.priority_label(value)}.")
      end

      def rename
        match = text.match(/\A(?:renomear|renomeia|muda(?:r)? o (?:titulo|nome)|altera(?:r)? o (?:titulo|nome)|titulo|nome)\s*(?:para|:)?\s+(.+)/) or return
        update({ title: original(match) }, "Título mudado para «#{original(match)}».")
      end

      def description
        if (match = text.match(/\A(?:nota|anota|acrescenta)\s*:?\s+(.+)/m))
          note = original(match)
          return update({ description: [ task.description.presence, note ].compact.join("\n\n") }, "Acrescentei a nota à descrição.")
        end
        match = text.match(/\A(?:descricao|descreve)\s*:?\s+(.+)/m) or return
        update({ description: original(match) }, "Descrição atualizada.")
      end

      def update(attributes, message)
        result = Update.call(task, params: attributes)
        result.success? ? ok(message) : failure(result.error)
      end

      # --- Partilhar e links -----------------------------------------------------
      def share
        match = text.match(/\A(?:partilha|partilhar|envia|enviar|manda|mandar)\b[^@]*?([^\s@,;:]+@[^\s@,;:]+\.[a-z]{2,})(?:\s*[,:;-]?\s*(.+))?/m) or return
        message = match[2] && original(match, 2).presence
        result = Shares::Create.call(sender: user, shareable: task, email: match[1], message: message)
        result.success? ? Reply.new(ok: true, text: result.message, changed: false, link: nil) : failure(result.message)
      end

      def link
        url = @raw[%r{https?://\S+}] or return
        label = @raw.sub(url, "").sub(/\A\s*(adiciona(r)?\s+)?(o\s+|um\s+)?link\s*:?/i, "").strip.presence
        record = user.links.new(linkable: task, url: url, label: label&.truncate(100))
        return failure("Não consegui guardar o link: #{record.errors.full_messages.to_sentence.downcase_first}.") unless record.save
        AuditLog.record("link.created", resource: record, user: user, linkable_type: "Task", linkable_id: task.id, host: record.host)
        ok("Link guardado.")
      end

      # --- Repetir ----------------------------------------------------------------
      def recurrence
        if text.match?(/\A(nao repetir|para(r)? de repetir|deixa(r)? de repetir|sem repeticao)\b/)
          return failure("Esta tarefa não se repete.") unless task.recurrence
          task.recurrence.destroy!
          AuditLog.record("task.recurrence_removed", resource: task, user: user)
          return ok("A tarefa deixou de se repetir.")
        end
        return unless text.match?(/\A(repetir|repete|repeticao|recorrente|todos os|todas as|todo o|toda a|cada|diariamente|semanalmente|mensalmente|anualmente)\b/)

        frequency = FREQUENCY_WORDS.find { |pattern, _| text.match?(pattern) }&.last
        return failure("De quanto em quanto tempo? Por exemplo «repetir todos os dias» ou «repetir a cada 2 semanas».") unless frequency
        interval = text[/\b(?:cada|de)\s+(\d+)\b/, 1]&.to_i || 1
        rule = task.recurrence || task.build_recurrence
        rule.assign_attributes(frequency: frequency, interval: interval)
        return failure(rule.errors.full_messages.to_sentence) unless rule.save
        AuditLog.record("task.recurrence_set", resource: task, user: user, frequency: frequency, interval: interval)
        ok("Repete #{ApplicationController.helpers.task_recurrence_summary(rule).downcase_first}.")
      end

      # --- Dependências -------------------------------------------------------------
      def dependency
        match = text.match(/\A(?:depende de|depois de|so depois de|bloqueada por|espera por)\s+(?:a\s+tarefa\s+)?(.+)/) or return
        name = original(match).delete("«»\"")
        blocker = user.tasks.active.open.where.not(id: task.id)
                      .where("LOWER(title) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(name.downcase)}%").order(:due_at).first
        return failure("Não encontrei nenhuma tarefa aberta com «#{name}».") unless blocker
        dependency = task.task_dependencies.build(blocker: blocker)
        return failure(dependency.errors.full_messages.to_sentence) unless dependency.save
        ok("Fica à espera de «#{blocker.title}».")
      end
  end
end
