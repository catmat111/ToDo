require "test_helper"

class JobApplicationTest < ActiveSupport::TestCase
  test "defaults to saved and requires a title" do
    application = users(:one).job_applications.new(title: "  ")
    assert_not application.valid?
    assert application.errors.of_kind?(:title, :blank)
    assert_equal "saved", application.status
  end

  test "strips title and company name" do
    application = create_job_application(title: "  Dev Rails  ", company_name: " ACME ")
    assert_equal "Dev Rails", application.title
    assert_equal "ACME", application.company_name
  end

  test "rejects unknown statuses" do
    application = create_job_application
    application.status = "hired"
    assert_not application.valid?
    assert application.errors.key?(:status)
  end

  test "transition table" do
    application = create_job_application
    assert_equal %w[applied withdrawn], application.allowed_transitions
    assert application.can_transition_to?(:applied)
    assert_not application.can_transition_to?("offer")
    assert_not application.can_transition_to?("interview")

    application.status = "interview"
    assert application.can_transition_to?("interview"), "another interview round is allowed"
    assert application.can_transition_to?("offer")
  end

  test "rejected and withdrawn are terminal" do
    %w[rejected withdrawn].each do |status|
      application = create_job_application(status: status)
      assert application.closed?
      assert_empty application.allowed_transitions
      JobApplication::STATUSES.each { |to| assert_not application.can_transition_to?(to) }
    end
    assert_not create_job_application(status: "offer").closed?
  end

  test "every status has a label and a transition entry" do
    JobApplication::STATUSES.each do |status|
      assert JobApplication::STATUS_LABELS.key?(status)
      assert JobApplication::TRANSITIONS.key?(status)
      JobApplication::TRANSITIONS[status].each { |to| assert_includes JobApplication::STATUSES, to }
    end
    assert_equal "Entrevista", JobApplication.status_label(:interview)
  end

  test "job listing must belong to the same user" do
    foreign_listing = users(:two).job_listings.create!(title: "Outra", url: "https://example.com/x/#{SecureRandom.hex(3)}")
    application = users(:one).job_applications.new(title: "Vaga", job_listing: foreign_listing)
    assert_not application.valid?
    assert application.errors.key?(:job_listing)
  end

  test "only one application per listing and user" do
    listing = users(:one).job_listings.create!(title: "Dev", url: "https://example.com/j/#{SecureRandom.hex(3)}")
    create_job_application(job_listing: listing)
    duplicate = users(:one).job_applications.new(title: "Outra", job_listing: listing)
    assert_not duplicate.valid?
    assert duplicate.errors.key?(:job_listing_id)
  end

  test "keeps title and company when the listing is deleted" do
    listing = users(:one).job_listings.create!(title: "Dev", company_name: "ACME",
                                               url: "https://example.com/j/#{SecureRandom.hex(3)}")
    application = create_job_application(job_listing: listing, title: "Dev", company_name: "ACME")
    listing.destroy!
    application.reload
    assert_nil application.job_listing_id
    assert_equal "Dev", application.title
    assert_equal "ACME", application.company_name
  end

  test "suggested task title depends on the status" do
    application = create_job_application(title: "Dev Rails")
    assert_equal "Candidatar-me: Dev Rails", application.suggested_task_title
    application.status = "interview"
    assert_equal "Preparar entrevista: Dev Rails", application.suggested_task_title
    application.status = "applied"
    assert_equal "Follow-up: Dev Rails", application.suggested_task_title
  end

  test "search matches title or company" do
    rails = create_job_application(title: "Programador Rails", company_name: "Alfa")
    design = create_job_application(title: "Designer", company_name: "Rails Studio")
    other = create_job_application(title: "Contabilista", company_name: "Beta")

    results = users(:one).job_applications.search("rails")
    assert_includes results, rails
    assert_includes results, design
    assert_not_includes results, other
    assert_equal 3, users(:one).job_applications.search("").count
  end

  test "destroying removes events and keeps tasks" do
    application = create_job_application
    application.job_application_events.create!(event_type: "saved", occurred_at: Time.current)
    task = create_task(job_application: application, task_type: "job")

    assert_difference -> { JobApplicationEvent.count }, -1 do
      application.destroy!
    end
    assert_nil task.reload.job_application_id
  end
end
