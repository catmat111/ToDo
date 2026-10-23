# The post-it chat outside a task page: adds tasks (with the dates they mention) and events.
# With the local LLM on, it reads the sentence in the background (AssistantReplyJob), so one
# message can hold several things; otherwise the rules (QuickAdd) answer right away.
class QuickAddsController < ApplicationController
  rate_limit to: 60, within: 1.minute, only: :create

  def create
    message = params[:message].to_s.strip.truncate(500)
    return ask_assistant(message) if OllamaClient.enabled?

    reply = QuickAdd.call(Current.user, message)
    record = reply.record

    respond_to do |format|
      format.turbo_stream do
        streams = [ turbo_stream.append("quickadd_messages", partial: "quick_adds/reply", locals: { message: message, reply: reply }) ]
        if record.is_a?(Task) && record.due_at&.in_time_zone&.to_date == Time.zone.today
          streams << turbo_stream.append("home-today-list", partial: "dashboard/task", locals: { task: record })
        end
        render turbo_stream: streams
      end
      format.html { redirect_back_or_to root_path, (reply.ok? ? :notice : :alert) => (reply.text || "Adicionado.") }
    end
  end

  private
    def ask_assistant(message)
      bubble_id = "assistant-#{SecureRandom.hex(6)}"
      AssistantReplyJob.perform_later(Current.user.id, message, bubble_id)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("quickadd_messages", html: helpers.tag.div(message, class: "quickadd__msg quickadd__msg--me")),
            turbo_stream.append("quickadd_messages", partial: "task_chats/assistant_bubble", locals: { id: bubble_id })
          ]
        end
        format.html { redirect_back_or_to root_path, notice: "A pensar… a resposta aparece no chat." }
      end
    end
end
