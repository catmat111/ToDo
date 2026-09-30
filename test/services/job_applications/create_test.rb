require "test_helper"

module JobApplications
  class CreateTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      Current.session = @user.sessions.create!
    end

    teardown { Current.reset }

    test "creates a manual application in saved with a saved event and an audit log" do
      result = nil
      assert_difference -> { @user.job_applications.count } => 1, -> { JobApplicationEvent.count } => 1,
                        -> { AuditLog.where(action: "job_application.created").count } => 1 do
        result = Create.call(user: @user, params: { title: "Dev Rails", company_name: "ACME", notes: "Remoto" })
      end

      assert result.success?
      assert result.created?
      application = result.job_application
      assert application.saved?
      assert_equal "Remoto", application.notes
      assert_equal [ "saved" ], application.job_application_events.map(&:event_type)
      assert_equal "manual", AuditLog.where(action: "job_application.created").last.metadata["source"]
    end

    test "prefills title and company from the listing" do
      listing = create_listing
      result = Create.call(user: @user, params: { job_listing_id: listing.id.to_s })

      assert result.success?
      assert_equal listing, result.job_application.job_listing
      assert_equal "Programador Rails", result.job_application.title
      assert_equal "Empresa X", result.job_application.company_name
    end

    test "explicit title wins over the listing's" do
      listing = create_listing
      result = Create.call(user: @user, params: { job_listing_id: listing.id, title: "Rails sénior" })
      assert_equal "Rails sénior", result.job_application.title
      assert_equal "Empresa X", result.job_application.company_name
    end

    test "returns the existing application instead of duplicating" do
      listing = create_listing
      first = Create.call(user: @user, params: { job_listing_id: listing.id }).job_application

      second = nil
      assert_no_difference -> { JobApplication.count } do
        second = Create.call(user: @user, params: { job_listing_id: listing.id })
      end
      assert second.success?
      assert_not second.created?
      assert_equal first, second.job_application
    end

    test "cannot use another user's listing" do
      foreign = create_listing(users(:two))
      assert_raises(ActiveRecord::RecordNotFound) do
        Create.call(user: @user, params: { job_listing_id: foreign.id })
      end
      assert_equal 0, @user.job_applications.count
    end

    test "fails without a title and creates nothing" do
      result = nil
      assert_no_difference -> { JobApplication.count } do
        result = Create.call(user: @user, params: { title: "", company_name: "ACME" })
      end
      assert result.failure?
      assert result.job_application.errors.key?(:title)
      assert_not result.job_application.persisted?
      assert_equal 0, JobApplicationEvent.count
    end

    test "ignores unexpected params such as status or user_id" do
      result = Create.call(user: @user, params: { title: "Dev", status: "offer", user_id: users(:two).id })
      assert result.job_application.saved?
      assert_equal @user, result.job_application.user
    end

    private
      def create_listing(user = @user)
        user.job_listings.create!(title: "Programador Rails", company_name: "Empresa X", location: "Lisboa",
                                  url: "https://example.com/jobs/#{SecureRandom.hex(4)}")
      end
  end
end
