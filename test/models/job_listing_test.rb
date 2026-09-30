require "test_helper"

class JobListingTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "normalize_url collapses tracking params, www, trailing slash, scheme and fragments" do
    canonical = JobListing.normalize_url("https://acme.pt/jobs/42")
    [
      "https://www.acme.pt/jobs/42/",
      "http://acme.pt/jobs/42",
      "https://ACME.pt/jobs/42?utm_source=linkedin&utm_medium=email",
      "https://www.acme.pt/jobs/42/?trk=abc&refId=xyz#apply",
      "  https://acme.pt/jobs/42?fbclid=1&gclid=2  "
    ].each do |variant|
      assert_equal canonical, JobListing.normalize_url(variant), variant
    end
  end

  test "normalize_url keeps meaningful params in a stable order" do
    assert_equal JobListing.normalize_url("https://pt.indeed.com/viewjob?jk=abc&from=serp"),
                 JobListing.normalize_url("https://pt.indeed.com/viewjob?from=serp&jk=abc&utm_campaign=x")
    assert_not_equal JobListing.normalize_url("https://pt.indeed.com/viewjob?jk=abc"),
                     JobListing.normalize_url("https://pt.indeed.com/viewjob?jk=def")
  end

  test "requires title and an http(s) url" do
    listing = @user.job_listings.new(title: "", url: "ftp://x")
    assert_not listing.valid?
    assert listing.errors.key?(:title)
    assert listing.errors.key?(:url)
  end

  test "sets normalized url and discovered_at" do
    listing = @user.job_listings.create!(title: "Dev", url: "https://www.acme.pt/jobs/1/?utm_source=x")
    assert_equal "https://acme.pt/jobs/1", listing.normalized_url
    assert_not_nil listing.discovered_at
  end

  test "the same job cannot be saved twice by the same user" do
    @user.job_listings.create!(title: "Dev", url: "https://acme.pt/jobs/1")
    duplicate = @user.job_listings.new(title: "Dev", url: "https://www.acme.pt/jobs/1/")
    assert_not duplicate.valid?

    assert users(:two).job_listings.new(title: "Dev", url: "https://acme.pt/jobs/1").valid?
  end

  test "external id is unique per user and source" do
    @user.job_listings.create!(title: "A", url: "https://linkedin.com/jobs/view/1", source: "linkedin", external_id: "1")
    assert_not @user.job_listings.new(title: "B", url: "https://linkedin.com/x", source: "linkedin", external_id: "1").valid?
    assert @user.job_listings.new(title: "B", url: "https://indeed.com/x", source: "indeed", external_id: "1").valid?
  end

  test "job search must belong to the same user" do
    foreign = users(:two).job_searches.create!(name: "Alheia", source: "linkedin")
    listing = @user.job_listings.new(title: "Dev", url: "https://acme.pt/1", job_search: foreign)
    assert_not listing.valid?
    assert listing.errors.key?(:job_search)
  end

  test "matching searches title and company case-insensitively" do
    rails = @user.job_listings.create!(title: "Programador Rails", company_name: "Acme", url: "https://acme.pt/1")
    other = @user.job_listings.create!(title: "Designer", company_name: "Rails Studio", url: "https://acme.pt/2")
    @user.job_listings.create!(title: "Contabilista", company_name: "Números", url: "https://acme.pt/3")

    assert_equal [ rails, other ].sort, @user.job_listings.matching("RAILS").to_a.sort
    assert_empty @user.job_listings.matching("100%")
  end

  test "application scopes" do
    saved = @user.job_listings.create!(title: "Com candidatura", url: "https://acme.pt/1")
    fresh = @user.job_listings.create!(title: "Nova", url: "https://acme.pt/2")
    create_job_application(@user, job_listing: saved)

    assert_equal [ saved ], @user.job_listings.with_application_for(@user).to_a
    assert_equal [ fresh ], @user.job_listings.without_application_for(@user).to_a
    assert_equal saved.job_applications.first, saved.application_for(@user)
    assert_nil fresh.application_for(@user)
  end

  test "host and source label" do
    listing = JobListing.new(url: "https://www.linkedin.com/jobs/view/1", source: "linkedin")
    assert_equal "linkedin.com", listing.host
    assert_equal "LinkedIn", listing.source_label
  end
end
