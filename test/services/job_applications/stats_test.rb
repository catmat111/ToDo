require "test_helper"

class JobApplications::StatsTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  def sent(title, applied_days_ago:, **attrs)
    app = create_job_application(@user, title: title, status: "applied", applied_at: applied_days_ago.days.ago, **attrs)
    app.job_application_events.create!(event_type: "applied", occurred_at: app.applied_at)
    app
  end

  test "funnel, response rate and days to first answer" do
    create_job_application(@user, title: "Só guardada")
    rejected = sent("Rejeitada", applied_days_ago: 20)
    rejected.update!(status: "rejected")
    rejected.job_application_events.create!(event_type: "rejected", occurred_at: 10.days.ago) # 10 days later
    interview = sent("Entrevista", applied_days_ago: 10)
    interview.update!(status: "interview")
    interview.job_application_events.create!(event_type: "interview", occurred_at: 6.days.ago) # 4 days later
    sent("Sem resposta", applied_days_ago: 30)

    stats = JobApplications::Stats.new(@user)

    assert_equal [ 4, 3, 1, 0 ], stats.funnel.map { |_, count, _| count }
    assert_equal 67, stats.response_rate # 2 of 3 sent got an answer
    assert_equal 7, stats.average_days_to_response # (10 + 4) / 2
    assert_equal [ "Sem resposta" ], stats.silent.map(&:title)
  end

  test "page renders, also with no data" do
    assert_not JobApplications::Stats.new(@user).any?
  end
end
