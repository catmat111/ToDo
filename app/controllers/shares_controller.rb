class SharesController < ApplicationController
  rate_limit to: 20, within: 10.minutes, only: :create,
             with: -> { redirect_back_or_to shares_path, alert: "Enviaste muitas partilhas seguidas. Espera uns minutos." }
  SHAREABLE_SCOPES = {
    "Task" => :tasks, "JobListing" => :job_listings, "JobApplication" => :job_applications
  }.freeze

  # Received (to accept/decline) and sent shares.
  def index
    @tab = params[:tab] == "sent" ? "sent" : "received"
    scope = @tab == "sent" ? Current.user.sent_shares.includes(:recipient) : Current.user.received_shares.includes(:sender)
    @shares = scope.recent.limit(100)
    @pending_count = Current.user.received_shares.pending.count
  end

  def create
    shareable = find_own_shareable
    result = Shares::Create.call(sender: Current.user, shareable: shareable,
                                 email: share_params[:email], message: share_params[:message])
    flash_key = result.success? ? :notice : :alert
    redirect_back_or_to shareable, flash_key => result.message
  end

  def accept
    share = Current.user.received_shares.find(params[:id])
    result = Shares::Respond.call(share, accept: true)
    if result.success? && result.copy
      redirect_to result.copy, notice: result.message
    else
      redirect_to shares_path, (result.success? ? :notice : :alert) => result.message
    end
  end

  def decline
    share = Current.user.received_shares.find(params[:id])
    result = Shares::Respond.call(share, accept: false)
    redirect_to shares_path, (result.success? ? :notice : :alert) => result.message
  end

  # The sender cancels a share that hasn't been answered yet.
  def destroy
    share = Current.user.sent_shares.pending.find(params[:id])
    share.destroy!
    redirect_to shares_path(tab: "sent"), notice: "Partilha cancelada.", status: :see_other
  end

  private
    def share_params
      params.expect(share: [ :shareable_type, :shareable_id, :email, :message ])
    end

    # Only the current user's own records can be shared (others give 404).
    def find_own_shareable
      scope = SHAREABLE_SCOPES.fetch(share_params[:shareable_type]) { raise ActiveRecord::RecordNotFound }
      Current.user.public_send(scope).find(share_params[:shareable_id])
    end
end
