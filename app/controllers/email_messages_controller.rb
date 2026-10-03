# "Respostas": job replies read from Gmail, waiting for the user to confirm.
class EmailMessagesController < ApplicationController
  before_action :set_email, only: %i[confirm ignore]

  def index
    Inbox::Rematch.call(Current.user) # applications added since the emails were read
    @tab = params[:tab] == "done" ? "done" : "pending"
    scope = Current.user.email_messages.includes(:job_application).recent
    @emails = (@tab == "done" ? scope.where.not(review_status: "pending") : scope.pending).limit(100)
    @pending_count = Current.user.email_messages.pending.count
    @connection = Current.user.mailbox_connection
    @applications = Current.user.job_applications.order(updated_at: :desc).limit(200)
  end

  def confirm
    application = Current.user.job_applications.find_by(id: params[:job_application_id])
    result = Inbox::Confirm.call(@email, job_application: application, outcome: params[:outcome])
    redirect_to email_messages_path, (result.success? ? :notice : :alert) => result.message
  end

  def ignore
    @email.update!(review_status: "ignored", reviewed_at: Time.current)
    redirect_to email_messages_path, notice: "Email ignorado."
  end

  private
    def set_email
      @email = Current.user.email_messages.find(params[:id])
    end
end
