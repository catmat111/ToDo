class NotificationsController < ApplicationController
  PER_PAGE = 30

  def index
    @filter = Notification::FILTERS.include?(params[:filter]) ? params[:filter] : "all"
    @page = [ params[:page].to_s.to_i, 1 ].max
    scope = Current.user.notifications.for_filter(@filter)
    @notifications = scope.recent.includes(:notifiable).offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @next_page = @notifications.size > PER_PAGE
    @notifications = @notifications.first(PER_PAGE)
    @unread_count = Current.user.notifications.unread.count
  end

  # Marks one notification as read. Opens the related record unless the user asked
  # to stay on the current page (the "Marcar como lida" button).
  def read
    notification = Current.user.notifications.find(params[:id])
    notification.mark_read!

    target = helpers.notifiable_path(notification) unless params[:stay].present?
    if target
      redirect_to target, status: :see_other
    else
      redirect_back_or_to notifications_path, notice: "Notificação marcada como lida.", status: :see_other
    end
  end

  def read_all
    count = Current.user.notifications.mark_all_read!
    AuditLog.record("notifications.read_all", count: count) if count.positive?
    notice = count.positive? ? "Todas as notificações foram marcadas como lidas." : "Não tinhas notificações por ler."
    redirect_back_or_to notifications_path, notice: notice, status: :see_other
  end
end
