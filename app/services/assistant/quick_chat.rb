module Assistant
  # The general chat (outside a task page), understood by the local LLM: one sentence can
  # hold several tasks and events ("ligar à mãe amanhã e marca jantar sábado às 20h").
  class QuickChat
    def self.call(user, message, client: OllamaClient.new)
      Conversation.new(client: client, tools: QuickTools.new(user, message), system: system_prompt,
                       fallback: "Não percebi. Diz-me o que tens de fazer e quando, por exemplo «ligar ao banco amanhã às 10h».").run(message)
    end

    def self.system_prompt
      <<~PROMPT
        És o assistente da app de tarefas «Tu Do». Respondes sempre em português de Portugal, numa frase curta.
        O utilizador escreve o que tem de fazer ou o que tem marcado. #{Conversation.today}

        Regras:
        - Algo a FAZER (ligar, enviar, estudar, comprar, pagar…) é uma tarefa: usa criar_tarefa.
        - Algo que ACONTECE a uma hora (jantar, reunião, aula, consulta, festa) é um evento: usa criar_evento. Se começar por «evento», é um evento.
        - Se a frase tiver várias coisas, cria cada uma (uma chamada por coisa).
        - O título é curto e sem a data. A data vai em «quando», com as palavras do utilizador; não faças contas de datas.
        - Se não percebes o que é para fazer, pergunta. Não inventes tarefas.
      PROMPT
    end
  end
end
