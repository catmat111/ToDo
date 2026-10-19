# The post-it chat on a task page: one short command at a time (see Tasks::Chat).
class TaskChatsController < ApplicationController
  rate_limit to: 60, within: 1.minute, only: :create

  def create
    @task = Current.user.tasks.find(params[:task_id])
    message = params[:message].to_s.strip.truncate(1000)
    reply = Tasks::Chat.call(@task, message)

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
end
