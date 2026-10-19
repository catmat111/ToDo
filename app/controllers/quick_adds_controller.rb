# The post-it chat outside a task page: adds a task (with the date it mentions) or an event.
class QuickAddsController < ApplicationController
  rate_limit to: 60, within: 1.minute, only: :create

  def create
    message = params[:message].to_s.strip.truncate(500)
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
end
