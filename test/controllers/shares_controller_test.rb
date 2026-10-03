require "test_helper"

class SharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @ana = users(:one)
    @bruno = users(:two)
    @task = create_task(@ana, title: "Rever CV", due_at: 2.days.from_now)
    @task.subtasks.create!(user: @ana, title: "Corrigir datas")
  end

  def share_task(email: @bruno.email_address)
    post shares_path, params: { share: { shareable_type: "Task", shareable_id: @task.id, email: email, message: "Ajudas?" } }
  end

  test "sending a task creates a pending share and notifies the recipient" do
    sign_in_as @ana
    assert_difference -> { Share.count } => 1, -> { @bruno.notifications.count } => 1 do
      share_task
    end
    assert_equal "pending", Share.last.status
  end

  test "unknown emails get the same message and create nothing" do
    sign_in_as @ana
    assert_no_difference -> { Share.count } do
      share_task(email: "ninguem@exemplo.pt")
    end
    assert_equal Shares::Create::SENT_MESSAGE, flash[:notice]
  end

  test "cannot share someone else's task" do
    sign_in_as @bruno
    share_task(email: @ana.email_address)
    assert_response :not_found
  end

  test "accepting copies the task with its subtasks into the recipient's account" do
    sign_in_as @ana
    share_task
    sign_out
    sign_in_as @bruno

    assert_difference -> { @bruno.tasks.count } => 2 do
      patch accept_share_path(Share.last)
    end
    copy = Share.last.reload.copy
    assert_equal @bruno, copy.user
    assert_equal "Rever CV", copy.title
    assert_equal 1, copy.subtasks.count
    assert @ana.notifications.exists?(notification_type: "share")
  end

  test "declining creates nothing and the sender cannot accept it" do
    sign_in_as @ana
    share_task
    patch accept_share_path(Share.last)
    assert_response :not_found

    sign_out
    sign_in_as @bruno
    assert_no_difference -> { @bruno.tasks.count } do
      patch decline_share_path(Share.last)
    end
    assert Share.last.reload.declined?
  end

  test "accepting a shared application creates a saved application for the recipient" do
    application = create_job_application(@ana, title: "Dev Júnior", status: "interview", notes: "privado")
    sign_in_as @ana
    post shares_path, params: { share: { shareable_type: "JobApplication", shareable_id: application.id, email: @bruno.email_address } }
    sign_out
    sign_in_as @bruno
    patch accept_share_path(Share.last)

    copy = @bruno.job_applications.last
    assert_equal "Dev Júnior", copy.title
    assert copy.saved?
    assert_nil copy.notes
  end
end
