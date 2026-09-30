require "test_helper"

class JobListings::ImporterTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @job_search = @user.job_searches.create!(name: "Rails", source: "linkedin", query: "rails")
  end

  def import(attributes, user: @user, job_search: nil)
    JobListings::Importer.call(user: user, attributes: attributes, job_search: job_search)
  end

  test "creates a listing and audits it" do
    result = nil
    assert_difference -> { @user.job_listings.count } => 1, -> { AuditLog.where(action: "job_listing.created").count } => 1 do
      result = import({ url: "https://acme.pt/jobs/1", title: "Dev Rails", company_name: "Acme" }, job_search: @job_search)
    end

    assert result.created?
    assert_not result.duplicate?
    assert_equal @job_search, result.listing.job_search
    assert_equal "linkedin", result.listing.source, "falls back to the search's source"
  end

  test "utm params, trailing slash and www variants collapse into one listing" do
    first = import({ url: "https://www.acme.pt/jobs/1/?utm_source=newsletter", title: "Dev" })
    assert first.created?

    [ "https://acme.pt/jobs/1", "http://www.acme.pt/jobs/1/", "https://acme.pt/jobs/1?utm_medium=email&trk=feed" ].each do |url|
      result = nil
      assert_no_difference -> { JobListing.count } do
        result = import({ url: url, title: "Dev (repetida)" })
      end
      assert_not result.created?
      assert result.duplicate?
      assert_equal first.listing, result.listing
    end
  end

  test "the same external id collapses even with a different url" do
    first = import({ url: "https://www.linkedin.com/jobs/view/3900000001/", title: "Dev" })
    assert_equal "linkedin", first.listing.source
    assert_equal "3900000001", first.listing.external_id

    result = import({ url: "https://www.linkedin.com/jobs/search/?currentJobId=3900000001&keywords=rails", title: "Dev" })
    assert result.duplicate?
    assert_equal first.listing, result.listing

    explicit = import({ url: "https://api.example.com/jobs/abc", title: "API", source: "indeed", external_id: "X1" })
    again = import({ url: "https://api.example.com/v2/jobs/abc", title: "API", source: "indeed", external_id: "X1" })
    assert explicit.created?
    assert_equal explicit.listing, again.listing
  end

  test "importing the same batch twice leaves one row per job" do
    batch = [
      { url: "https://www.linkedin.com/jobs/view/3900000001/?trk=abc", title: "Dev A", company_name: "Acme" },
      { url: "https://pt.indeed.com/viewjob?jk=1a2b3c", title: "Dev B", company_name: "Beta" },
      { url: "https://careers.gamma.pt/jobs/42/", title: "Dev C", company_name: "Gamma" }
    ]

    first_run = JobListings::Importer.call_many(user: @user, items: batch, job_search: @job_search)
    assert first_run.all?(&:created?)

    assert_no_difference -> { JobListing.count } do
      second_run = JobListings::Importer.call_many(user: @user, items: batch, job_search: @job_search)
      assert second_run.none?(&:created?)
      assert_equal first_run.map(&:listing), second_run.map(&:listing)
    end
    assert_equal 3, @user.job_listings.count
  end

  test "the same job can be saved by different users" do
    import({ url: "https://acme.pt/jobs/1", title: "Dev" })
    other = import({ url: "https://acme.pt/jobs/1", title: "Dev" }, user: users(:two))
    assert other.created?
    assert_equal users(:two), other.listing.user
  end

  test "duplicates fill in blank fields without overwriting" do
    first = import({ url: "https://acme.pt/jobs/1", title: "Dev", company_name: "Acme" })
    import({ url: "https://acme.pt/jobs/1/", title: "Outro título", company_name: "Outra", location: "Lisboa",
             description: "Descrição", job_search_id: @job_search.id })

    listing = first.listing.reload
    assert_equal "Dev", listing.title
    assert_equal "Acme", listing.company_name
    assert_equal "Lisboa", listing.location
    assert_equal "Descrição", listing.description
    assert_equal @job_search, listing.job_search
  end

  test "job_search_id of another user is rejected" do
    foreign = users(:two).job_searches.create!(name: "Alheia", source: "indeed")

    result = nil
    assert_no_difference -> { JobListing.count } do
      result = import({ url: "https://acme.pt/jobs/9", title: "Dev", job_search_id: foreign.id })
    end
    assert_not result.success?
    assert result.listing.errors.key?(:job_search)
  end

  test "an explicit job search of another user is rejected by validation" do
    foreign = users(:two).job_searches.create!(name: "Alheia", source: "indeed")
    result = import({ url: "https://acme.pt/jobs/9", title: "Dev" }, job_search: foreign)
    assert_not result.success?
    assert result.listing.errors.key?(:job_search)
  end

  test "source defaults to the url, then the search" do
    assert_equal "indeed", import({ url: "https://pt.indeed.com/viewjob?jk=zz1", title: "X" }, job_search: @job_search).listing.source
    assert_equal "linkedin", import({ url: "https://acme.pt/jobs/77", title: "Y" }, job_search: @job_search).listing.source
    assert_equal "other", import({ url: "https://acme.pt/jobs/78", title: "Z", source: "other" }, job_search: @job_search).listing.source
  end

  test "invalid attributes return an unsaved listing with errors" do
    result = import({ url: "not-a-url", title: "" })
    assert_not result.created?
    assert_not result.duplicate?
    assert result.listing.new_record?
    assert result.listing.errors.key?(:title)
    assert result.listing.errors.key?(:url)
  end

  test "ignores attributes outside the whitelist" do
    result = import({ url: "https://acme.pt/jobs/1", title: "Dev", user_id: users(:two).id, normalized_url: "x" })
    assert_equal @user, result.listing.user
    assert_equal "https://acme.pt/jobs/1", result.listing.normalized_url
  end
end
