require "test_helper"

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @task = create_task(title: "Rever apontamentos")
    @unread = @user.notifications.create!(notification_type: "reminder", notifiable: @task,
                                          title: "Lembrete: Rever apontamentos", body: "O prazo termina amanhã.")
    @read = @user.notifications.create!(notification_type: "system", title: "Bem-vinda", read_at: 1.hour.ago)
    @foreign = users(:two).notifications.create!(notification_type: "system", title: "Notificação do Bruno")
    sign_in_as @user
  end

  test "index lists all the user's notifications" do
    get notifications_path

    assert_response :success
    assert_select ".tabs__link.is-active", "Todas"
    assert_select "#notifications .notification", 2
    assert_select "##{ActionView::RecordIdentifier.dom_id(@unread)}.notification--unread"
    assert_select "a[href=?]", task_path(@task)
    assert_select "form[action=?]", read_notification_path(@unread)
    assert_select "form[action=?]", read_notification_path(@read), count: 0
    assert_select ".notification__body", "O prazo termina amanhã."
    assert_no_match "Notificação do Bruno", response.body
  end

  test "index can show only unread notifications" do
    get notifications_path(filter: "unread")

    assert_response :success
    assert_select ".tabs__link.is-active", /Por ler/
    assert_select "#notifications .notification", 1
    assert_no_match "Bem-vinda", response.body
  end

  test "index shows an empty state" do
    @user.notifications.delete_all
    get notifications_path(filter: "unread")
    assert_select ".empty-state__title", "Nada por ler"
  end

  test "read marks the notification and opens the related task" do
    patch read_notification_path(@unread)

    assert_redirected_to task_path(@task)
    assert @unread.reload.read?
  end

  test "read with stay goes back instead of opening the task" do
    patch read_notification_path(@unread), params: { stay: 1 }, headers: { "HTTP_REFERER" => notifications_url }

    assert_redirected_to notifications_url
    assert @unread.reload.read?
  end

  test "read without a notifiable goes back to the list" do
    patch read_notification_path(@read)
    assert_redirected_to notifications_path
  end

  test "read_all marks every unread notification of the user" do
    another = @user.notifications.create!(notification_type: "task_due", title: "Prazo")

    patch read_all_notifications_path

    assert_redirected_to notifications_path
    assert_equal "Todas as notificações foram marcadas como lidas.", flash[:notice]
    assert @unread.reload.read?
    assert another.reload.read?
    assert_not @foreign.reload.read?
    assert_equal "notifications.read_all", AuditLog.last.action
  end

  test "another user's notification cannot be read" do
    patch read_notification_path(@foreign)

    assert_response :not_found
    assert_not @foreign.reload.read?
  end

  test "requires authentication" do
    sign_out
    get notifications_path
    assert_redirected_to new_session_path
  end

  test "index paginates" do
    NotificationsController::PER_PAGE.times { |i| @user.notifications.create!(notification_type: "system", title: "Aviso #{i}") }

    get notifications_path
    assert_select "#notifications .notification", NotificationsController::PER_PAGE
    assert_select "a[href=?]", notifications_path(page: 2), text: /Mais antigas/

    get notifications_path(page: 2)
    assert_select "#notifications .notification", 2
    assert_select "a[href=?]", notifications_path(page: 1), text: /Anteriores/
  end

  test "index tolerates malformed filter and page params" do
    get notifications_path, params: { filter: [ "unread" ], page: [ "2" ] }

    assert_response :success
    assert_select ".tabs__link.is-active", "Todas"
  end

  test "read_all with nothing unread says so" do
    @user.notifications.mark_all_read!
    patch read_all_notifications_path
    assert_equal "Não tinhas notificações por ler.", flash[:notice]
  end
end
