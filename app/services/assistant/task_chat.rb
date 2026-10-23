module Assistant
  # Free-text requests about one task, understood by the local LLM (OllamaClient) and
  # carried out by TaskTools. Used when the rule-based Tasks::Chat doesn't understand.
  #
  #   reply = Assistant::TaskChat.call(task, "divide isto em 3 passos e lembra-me na véspera")
  #   reply.text     # => "Criei 3 subtarefa(s): … Lembrete criado para 26/10/2026 18:00."
  #   reply.changed? # => true
  class TaskChat
    def self.call(task, message, client: OllamaClient.new)
      Conversation.new(client: client, tools: TaskTools.new(task), system: system_prompt(task),
                       fallback: "Não percebi o que queres mudar. Experimenta escrever de outra forma, ou «ajuda».").run(message)
    end

    def self.system_prompt(task)
      <<~PROMPT
        És o assistente da app de tarefas «Tu Do». Respondes sempre em português de Portugal, numa ou duas frases curtas.
        O utilizador está a ver esta tarefa:
        - título: #{task.title}
        - estado: #{task.status_label}; prioridade: #{Task.priority_label(task.priority)}
        - prazo: #{task.due_at ? task.due_at.strftime("%Y-%m-%dT%H:%M") : "sem prazo"}
        - subtarefas: #{task.subtasks.map(&:title).join(", ").presence || "nenhuma"}
        - etiquetas: #{task.tags.map(&:name).join(", ").presence || "nenhuma"}

        #{Conversation.today}

        Regras:
        - Usa as ferramentas para fazer o que o utilizador pede a ESTA tarefa. Podes usar várias, cada uma só uma vez por pedido.
        - Faz tudo o que foi pedido: se pedir duas coisas (ex.: prioridade e etiqueta), chama as duas ferramentas.
        - Datas: copia as palavras do utilizador (ex.: «sexta às 15h», «na véspera», «1 dia antes»). Não faças contas de datas.
        - Se faltar informação essencial (por exemplo, a hora não é clara e importa), pergunta em vez de adivinhar.
        - Não inventes resultados: diz só o que as ferramentas confirmaram. Se uma ferramenta der erro, explica-o.
        - Não podes apagar tarefas; para isso o utilizador usa o botão «⋯» da página.
      PROMPT
    end
  end
end
