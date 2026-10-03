require "test_helper"

class JobApplications::FollowUpsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(follow_up_after_days: 7)
  end

  def sent(title, days_ago)
    app = create_job_application(@user, title: title, status: "applied", applied_at: days_ago.days.ago)
    app.job_application_events.create!(event_type: "applied", occurred_at: app.applied_at)
    app
  end

  test "creates one follow-up task for silent applications, only once" do
    silent = sent("Sem notícias", 10)
    sent("Recente", 3)
    with_news = sent("Com nota", 10)
    with_news.job_application_events.create!(event_type: "note", occurred_at: 5.days.ago, notes: "Liguei")

    assert_difference -> { @user.tasks.count } => 1, -> { @user.notifications.count } => 1 do
      assert_equal 1, JobApplications::FollowUps.call
    end
    task = @user.tasks.last
    assert_equal "Follow-up: Sem notícias", task.title
    assert_equal silent, task.job_application
    assert silent.reload.follow_up_suggested_at.present?

    assert_no_difference -> { @user.tasks.count } do
      JobApplications::FollowUps.call
    end
  end

  test "0 days turns it off" do
    @user.update!(follow_up_after_days: 0)
    sent("Sem notícias", 30)
    assert_equal 0, JobApplications::FollowUps.call
  end
end
