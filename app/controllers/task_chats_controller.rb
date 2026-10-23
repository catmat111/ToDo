# The post-it chat on a task page: short commands go through the rules (Tasks::Chat);
# what they don't understand goes to the local LLM in the background (AssistantReplyJob).
class TaskChatsController < ApplicationController
  rate_limit to: 60, within: 1.minute, only: :create

  def create
    @task = Current.user.tasks.find(params[:task_id])
    message = params[:message].to_s.strip.truncate(1000)
    reply = Tasks::Chat.call(@task, message)
    return ask_assistant(message) if !reply.understood? && OllamaClient.enabled?

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.append("quickadd_messages", partial: "task_chats/reply", locals: { message: message, reply: reply }) ]
        if reply.changed?
          @task.reload
          @subtasks = @task.preload_subtasks
          streams << turbo_stream.replace("task_page", partial: "tasks/page")
        end
        render turbo_stream: streams
      end
      format.html { redirect_to @task, (reply.ok? ? :notice : :alert) => reply.text }
    end
  end

  private
    def ask_assistant(message)
      bubble_id = "assistant-#{SecureRandom.hex(6)}"
      AssistantReplyJob.perform_later(Current.user.id, message, bubble_id, @task.id)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("quickadd_messages", html: helpers.tag.div(message, class: "quickadd__msg quickadd__msg--me")),
            turbo_stream.append("quickadd_messages", partial: "task_chats/assistant_bubble", locals: { id: bubble_id })
          ]
        end
        format.html { redirect_to @task, notice: "A pensar… a resposta aparece no chat." }
      end
    end
end
