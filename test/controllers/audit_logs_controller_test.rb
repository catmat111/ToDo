require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "index shows only the signed-in user's entries" do
    AuditLog.record("user.password_changed", resource: @user, user: @user)
    AuditLog.record("calendar.connected", user: users(:two))

    get audit_logs_path

    assert_response :success
    assert_select "h1", "Histórico"
    assert_select ".history-entry", 1
    assert_select ".history-entry__label", "Alteraste a password"
    assert_select "a[href=?]", profile_path, text: "O teu perfil"
    assert_no_match "Ligaste o Google Calendar", response.body
  end

  test "index links to resources that still exist" do
    task = create_task(@user, title: "Estudar Rails")
    AuditLog.record("task.completed", resource: task, user: @user, from: "pending", to: "completed")

    get audit_logs_path

    assert_select ".history-entry__label", "Concluíste uma tarefa"
    assert_select "a.history-entry__resource[href=?]", task_path(task), text: /Estudar Rails/
    assert_select ".history-entry__details", /de Pendente para Concluída/
  end

  test "index does not crash when the resource was deleted" do
    task = create_task(@user)
    AuditLog.record("task.deleted", resource: task, user: @user, title: task.title)
    task.destroy!

    get audit_logs_path

    assert_response :success
    assert_select ".history-entry__label", "Eliminaste uma tarefa"
    assert_select "a[href=?]", task_path(task), count: 0
    assert_select "span.history-entry__resource", /Tarefa \(já não existe\)/
  end

  test "index never links another user's record even if an entry points to it" do
    foreign_task = create_task(users(:two), title: "Segredo do Bruno")
    AuditLog.record("task.updated", resource: foreign_task, user: @user)

    get audit_logs_path

    assert_response :success
    assert_no_match "Segredo do Bruno", response.body
    assert_select "a[href=?]", task_path(foreign_task), count: 0
  end

  test "index maps job application status changes to pt labels" do
    application = create_job_application(@user, title: "Programadora Júnior")
    AuditLog.record("job_application.status_changed", resource: application, user: @user, from: "applied", to: "interview")

    get audit_logs_path

    assert_select ".history-entry__label", "Mudaste o estado de uma candidatura"
    assert_select "a[href=?]", job_application_path(application)
    assert_select ".history-entry__details", /de Candidatura enviada para Entrevista/
  end

  test "index humanizes unknown actions and hides sensitive metadata" do
    AuditLog.record("tag.merged", user: @user, access_token: "abc123", count: 3)

    get audit_logs_path

    assert_select ".history-entry__label", "Tag merged"
    assert_select ".history-entry__details", /Total: 3/
    assert_no_match "abc123", response.body
  end

  test "index filters by scope" do
    AuditLog.record("user.updated", resource: @user, user: @user)
    AuditLog.record("job_listing.created", user: @user)
    AuditLog.record("job_search.run", user: @user)

    get audit_logs_path(scope: "emprego")

    assert_select ".history-entry", 2
    assert_select ".tabs__link.is-active", "Emprego"
    assert_no_match "Atualizaste o perfil", response.body
  end

  test "index ignores an unknown scope" do
    AuditLog.record("user.updated", resource: @user, user: @user)

    get audit_logs_path(scope: "' OR 1=1 --")

    assert_response :success
    assert_select ".history-entry", 1
    assert_select ".tabs__link.is-active", "Tudo"
  end

  test "index shows an empty state" do
    get audit_logs_path

    assert_response :success
    assert_select ".empty-state"
  end

  test "index groups entries by day" do
    AuditLog.record("user.updated", resource: @user, user: @user)
    AuditLog.record("user.signed_in", resource: @user, user: @user).update_columns(created_at: 3.days.ago)

    get audit_logs_path

    assert_select ".history__day", 2
    assert_select ".history__day-title", "Hoje"
  end
end
