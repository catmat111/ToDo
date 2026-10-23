# Answers a chat message with the local LLM, then swaps the "a pensar…" bubble for the
# answer and refreshes the page if something changed. With a task it acts on that task
# (Assistant::TaskChat); without, it adds tasks and events (Assistant::QuickChat).
class AssistantReplyJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # Tests swap in a fake (no Ollama needed).
  class_attribute :client

  def perform(user_id, message, bubble_id, task_id = nil)
    user = User.find(user_id)
    task = user.tasks.find(task_id) if task_id
    stream = [ user, :assistant ]
    reply = Time.use_zone(user.time_zone) { answer(user, task, message) }

    Turbo::StreamsChannel.broadcast_replace_to(stream, target: bubble_id, partial: "task_chats/assistant_bubble",
                                                       locals: { id: bubble_id, text: reply.text, state: reply.respond_to?(:ok?) && !reply.ok? ? "error" : "done" })
    Turbo::StreamsChannel.broadcast_refresh_to(stream) if reply.changed?
  end

  private
    def answer(user, task, message)
      llm = client || OllamaClient.new
      task ? Assistant::TaskChat.call(task, message, client: llm) : Assistant::QuickChat.call(user, message, client: llm)
    rescue OllamaClient::Error => e
      Rails.logger.warn("[assistant] #{e.message}")
      task ? offline_reply : rules_reply(user, message)
    end

    # Ollama off: the general chat still adds the task/event with the rules (QuickAdd).
    def rules_reply(user, message)
      added = QuickAdd.call(user, message)
      record = added.record
      text = if !added.ok? then added.text
      elsif record.is_a?(Event) then "Marquei o evento «#{record.title}»."
      else "Adicionei «#{record.title}»."
      end
      Assistant::Conversation::Reply.new(text: text, changed: added.ok?)
    end

    def offline_reply
      Assistant::Conversation::Reply.new(changed: false,
                                         text: "O assistente está desligado (Ollama). Experimenta um comando simples, ou escreve «ajuda».")
    end
end
