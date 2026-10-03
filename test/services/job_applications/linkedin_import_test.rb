require "test_helper"

class JobApplications::LinkedinImportTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("docs/exemplos/linkedin_job_applications_exemplo.csv")

  setup { @user = users(:one) }

  def import
    File.open(SAMPLE) { |io| JobApplications::LinkedinImport.call(user: @user, io: io) }
  end

  test "imports applications as sent, with the real date, companies and recruiters" do
    summary = import

    assert_equal 3, summary.created
    assert_equal 1, summary.skipped # same job twice in the file (tracking param / no www)
    application = @user.job_applications.find_by!(title: "Programadora Júnior Ruby on Rails")
    assert application.applied?
    assert_equal Time.zone.local(2026, 9, 15, 10, 12), application.applied_at
    assert_equal "ACME", application.company.name
    assert_equal "rita.sousa@acme.pt", application.contact.email
    assert_match "CV_Catarina_2026.pdf", application.notes
    assert_equal "linkedin", application.job_listing.source
  end

  test "importing the same file again adds nothing" do
    import
    assert_no_difference -> { @user.job_applications.count } do
      summary = import
      assert_equal 4, summary.skipped
    end
  end

  test "a saved application for the same job is moved to sent" do
    listing = @user.job_listings.create!(title: "Software Engineer (Graduate)", url: "https://www.linkedin.com/jobs/view/4023456789/")
    saved = JobApplications::Create.call(user: @user, params: { job_listing_id: listing.id }).job_application

    summary = import
    assert_equal 1, summary.updated
    assert saved.reload.applied?
  end

  test "rejects files that are not the LinkedIn export" do
    assert_raises(ArgumentError) do
      JobApplications::LinkedinImport.call(user: @user, io: StringIO.new("nome,idade\nAna,30\n"))
    end
  end
end
