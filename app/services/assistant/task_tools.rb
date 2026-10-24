module Assistant
  # What the assistant may do to one task. The task and its owner are fixed here, so the
  # model never picks ids — and it can't delete.
  class TaskTools < Tools
    PRIORITIES = { "baixa" => 0, "normal" => 1, "alta" => 2, "urgente" => 3 }.freeze
    FREQUENCIES = { "diaria" => "daily", "semanal" => "weekly", "mensal" => "monthly", "anual" => "yearly" }.freeze
    STATUS_ACTIONS = { "iniciar" => "in_progress", "cancelar" => "cancelled", "reabrir" => "pending" }.freeze

    DATE_HINT = Dates::HINT

    DEFINITIONS = [
      function("adicionar_subtarefas", "Cria uma ou mais subtarefas (passos) dentro desta tarefa.",
               { titulos: { type: "array", items: { type: "string" }, description: "Título de cada subtarefa" } }),
      function("adicionar_lembrete", "Cria um lembrete para esta tarefa.",
               { data_hora: { type: "string", description: DATE_HINT },
                 canal: { type: "string", enum: %w[app email], description: "Onde avisar; app por omissão" } }, %i[data_hora]),
      function("mudar_prazo", "Muda o prazo (data de entrega) desta tarefa. Vazio tira o prazo.",
               { data_hora: { type: "string", description: "#{DATE_HINT}. Só a data (AAAA-MM-DD) se não houver hora." } }),
      function("mudar_inicio", "Marca quando a tarefa começa (ex.: «começa amanhã»).", { data_hora: { type: "string", description: DATE_HINT } }),
      function("adicionar_etiquetas", "Põe etiquetas nesta tarefa.", { nomes: { type: "array", items: { type: "string" } } }),
      function("remover_etiquetas", "Tira etiquetas desta tarefa.", { nomes: { type: "array", items: { type: "string" } } }),
      function("mudar_prioridade", "Muda a prioridade desta tarefa.", { prioridade: { type: "string", enum: PRIORITIES.keys } }),
      function("mudar_titulo", "Muda o título desta tarefa.", { titulo: { type: "string" } }),
      function("escrever_descricao", "Escreve na descrição. modo 'acrescentar' junta ao que lá está; 'substituir' troca tudo.",
               { texto: { type: "string" }, modo: { type: "string", enum: %w[acrescentar substituir] } }, %i[texto]),
      function("concluir_tarefa", "Marca esta tarefa como concluída."),
      function("mudar_estado", "Muda o estado JÁ: iniciar = começar a trabalhar nela agora; cancelar; reabrir. Para marcar uma data de início usa mudar_inicio.",
               { acao: { type: "string", enum: STATUS_ACTIONS.keys } }),
      function("repetir_tarefa", "Faz a tarefa repetir-se. frequencia 'nenhuma' deixa de repetir.",
               { frequencia: { type: "string", enum: FREQUENCIES.keys + [ "nenhuma" ] },
                 intervalo: { type: "integer", description: "De quantas em quantas (1 = todas)" } }, %i[frequencia]),
      function("partilhar_tarefa", "Envia esta tarefa a outra pessoa da app, pelo email dela.",
               { email: { type: "string" }, mensagem: { type: "string" } }, %i[email]),
      function("duplicar_tarefa", "Cria uma cópia desta tarefa (com etiquetas, links e subtarefas)."),
      function("adicionar_link", "Guarda um link nesta tarefa.", { url: { type: "string" }, nome: { type: "string" } }, %i[url])
    ].freeze

    def initialize(task)
      super()
      @task = task
      @user = task.user
    end

    private
      attr_reader :task, :user

      def parse_time(value, relative_to_due: false) = Dates.parse(value, due_at: (task.due_at if relative_to_due))
      def fmt(time) = Dates.format(time)

      def tool_adicionar_subtarefas(args)
        return "Erro: esta tarefa já está no nível máximo de subtarefas." if task.ancestors.size + 1 >= Task::MAX_DEPTH
        titles = Array(args["titulos"]).map { |t| t.to_s.strip }.compact_blank.first(10)
        created = titles.count do |title|
          Tasks::Create.call(user: user, params: { title: title, parent_task_id: task.id, task_type: task.task_type }).success?
        end
        created.positive? ? done("Criei #{created} subtarefa(s): #{titles.join(", ")}.") : "Erro: não criei nenhuma subtarefa."
      end

      def tool_adicionar_lembrete(args)
        time, has_hour = parse_time(args["data_hora"], relative_to_due: true)
        return "Erro: não percebi a data «#{args["data_hora"]}»." unless time
        time = time.change(hour: 9) unless has_hour
        reminder = task.reminders.build(remind_at: time, channel: args["canal"] == "email" ? "email" : "in_app")
        return "Erro: #{reminder.errors.full_messages.to_sentence}" unless reminder.save
        AuditLog.record("reminder.created", resource: reminder, user: user, task_id: task.id, channel: reminder.channel)
        done("Lembrete criado para #{fmt(time)}.")
      rescue ActiveRecord::RecordNotUnique
        "Erro: já existe um lembrete para esse momento."
      end

      def tool_mudar_prazo(args)
        raw = args["data_hora"]
        unless raw.blank?
          time, has_hour = parse_time(raw)
          return "Erro: não percebi a data «#{raw}»." unless time
          time = time.end_of_day unless has_hour
        end
        update({ due_at: time }, time ? "Prazo mudado para #{fmt(time)}." : "Prazo removido.")
      end

      def tool_mudar_inicio(args)
        time, has_hour = parse_time(args["data_hora"])
        return "Erro: não percebi a data «#{args["data_hora"]}»." unless time
        time = time.change(hour: 9) unless has_hour
        update({ starts_at: time }, "Início mudado para #{fmt(time)}.")
      end

      def tool_adicionar_etiquetas(args)
        added = tags_named(user, args["nomes"]).reject { |tag| task.tags.include?(tag) }
        return "Essas etiquetas já estavam na tarefa." if added.empty?
        task.tags << added
        AuditLog.record("task.updated", resource: task, user: user, fields: [ "tags" ])
        done("Etiquetas adicionadas: #{added.map(&:name).join(", ")}.")
      end

      def tool_remover_etiquetas(args)
        names = Array(args["nomes"]).map { |n| n.to_s.delete_prefix("#").squish.downcase }
        removed = task.tags.select { |tag| names.include?(tag.name.downcase) }
        return "A tarefa não tem essas etiquetas." if removed.empty?
        task.tags.delete(*removed)
        AuditLog.record("task.updated", resource: task, user: user, fields: [ "tags" ])
        done("Etiquetas retiradas: #{removed.map(&:name).join(", ")}.")
      end

      def tool_mudar_prioridade(args)
        value = PRIORITIES[args["prioridade"].to_s.downcase] or return "Erro: prioridade tem de ser #{PRIORITIES.keys.join(", ")}."
        update({ priority: value }, "Prioridade: #{Task.priority_label(value)}.")
      end

      def tool_mudar_titulo(args)
        title = args["titulo"].to_s.squish.presence or return "Erro: falta o título."
        update({ title: title }, "Título mudado para «#{title}».")
      end

      def tool_escrever_descricao(args)
        text = args["texto"].to_s.strip.presence or return "Erro: falta o texto."
        description = args["modo"] == "substituir" ? text : [ task.description.presence, text ].compact.join("\n\n")
        update({ description: description }, "Descrição atualizada.")
      end

      def tool_concluir_tarefa(_args)
        result = Tasks::Complete.call(task)
        result.success? ? done("Tarefa concluída.") : "Erro: #{result.error}"
      end

      def tool_mudar_estado(args)
        to = STATUS_ACTIONS[args["acao"].to_s] or return "Erro: ação tem de ser #{STATUS_ACTIONS.keys.join(", ")}."
        result = Tasks::ChangeStatus.call(task, to: to)
        result.success? ? done("Estado: #{task.status_label}.") : "Erro: #{result.error}"
      end

      def tool_repetir_tarefa(args)
        if args["frequencia"] == "nenhuma"
          return "A tarefa não se repetia." unless task.recurrence
          task.recurrence.destroy!
          AuditLog.record("task.recurrence_removed", resource: task, user: user)
          return done("A tarefa deixou de se repetir.")
        end
        frequency = FREQUENCIES[args["frequencia"].to_s] or return "Erro: frequência inválida."
        interval = [ args["intervalo"].to_i, 1 ].max
        rule = task.recurrence || task.build_recurrence
        rule.update!(frequency: frequency, interval: interval)
        AuditLog.record("task.recurrence_set", resource: task, user: user, frequency: frequency, interval: interval)
        done("A tarefa repete-se: #{TaskRecurrence.frequency_label(frequency).downcase}, a cada #{interval}.")
      end

      def tool_partilhar_tarefa(args)
        result = Shares::Create.call(sender: user, shareable: task, email: args["email"], message: args["mensagem"].presence)
        result.success? ? result.message : "Erro: #{result.message}"
      end

      def tool_adicionar_link(args)
        link = user.links.new(linkable: task, url: args["url"].to_s.strip, label: args["nome"].to_s.strip.presence&.truncate(100))
        return "Erro: #{link.errors.full_messages.to_sentence}" unless link.save
        AuditLog.record("link.created", resource: link, user: user, linkable_type: "Task", linkable_id: task.id, host: link.host)
        done("Link guardado.")
      end

      def tool_duplicar_tarefa(_args)
        result = Tasks::Duplicate.call(task)
        result.success? ? "Criei uma cópia: «#{result.task.title}»." : "Erro: #{result.error}"
      end

      def update(attributes, message)
        result = Tasks::Update.call(task, params: attributes)
        result.success? ? done(message) : "Erro: #{result.error}"
      end
  end
end
