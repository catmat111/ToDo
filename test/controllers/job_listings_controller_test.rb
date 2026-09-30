require "test_helper"

class JobListingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job_search = @user.job_searches.create!(name: "Rails Lisboa", source: "linkedin", query: "rails")
    @listing = @user.job_listings.create!(title: "Programador Rails", company_name: "Acme", location: "Lisboa",
                                          url: "https://www.linkedin.com/jobs/view/3900000001/", source: "linkedin",
                                          job_search: @job_search, description: "Primeira linha\n\nSegunda linha")
    sign_in_as(@user)
  end

  test "index lists listings with source and discovered time" do
    get job_listings_url
    assert_response :success
    assert_select "h1", "Vagas"
    assert_select ".job-listing-item", 1
    assert_select ".job-listing-item .list__title", "Programador Rails"
    assert_select ".job-listing-item .job-source", "LinkedIn"
    assert_select ".job-listing-item", text: /Descoberta há/
  end

  test "index shows the application status when saved as application" do
    create_job_application(@user, job_listing: @listing, status: "applied")
    get job_listings_url
    assert_select ".job-listing-item .badge--applied"
  end

  test "index filters by text, source, search and state" do
    other = @user.job_listings.create!(title: "Designer", company_name: "Beta", url: "https://pt.indeed.com/viewjob?jk=b1", source: "indeed")
    create_job_application(@user, job_listing: other)

    get job_listings_url(q: "acme")
    assert_select ".job-listing-item", 1
    assert_select ".list__title", "Programador Rails"

    get job_listings_url(source: "indeed")
    assert_select ".list__title", "Designer"
    assert_select ".job-listing-item", 1

    get job_listings_url(job_search_id: @job_search.id)
    assert_select ".list__title", "Programador Rails"
    assert_select ".job-listing-item", 1

    get job_listings_url(state: "saved")
    assert_select ".list__title", "Designer"
    assert_select ".job-listing-item", 1

    get job_listings_url(state: "new")
    assert_select ".list__title", "Programador Rails"
    assert_select ".job-listing-item", 1

    get job_listings_url(q: "nada disto")
    assert_select ".empty-state", text: /Nenhuma vaga corresponde/
  end

  test "index never shows other users' listings" do
    users(:two).job_listings.create!(title: "Vaga do Bruno", url: "https://acme.pt/bruno")
    get job_listings_url
    assert_no_match "Vaga do Bruno", response.body
  end

  test "show displays details and the save-as-application button" do
    get job_listing_url(@listing)
    assert_response :success
    assert_select "h1", "Programador Rails"
    assert_select ".job-listing-description p", 2
    assert_select "a[href=?][target=_blank][rel='noopener noreferrer']", @listing.url
    assert_select "form[action=?]", job_applications_path do
      assert_select "input[name='job_application[job_listing_id]'][value=?]", @listing.id.to_s
    end
  end

  test "show links to the existing application instead" do
    application = create_job_application(@user, job_listing: @listing)
    get job_listing_url(@listing)
    assert_select "a[href=?]", job_application_path(application)
    assert_select "form[action=?]", job_applications_path, 0
  end

  test "new prefills the search" do
    get new_job_listing_url(job_search_id: @job_search.id)
    assert_response :success
    assert_select "select[name='job_listing[job_search_id]'] option[selected][value=?]", @job_search.id.to_s
    assert_select "select[name='job_listing[source]'] option[selected][value=linkedin]"
  end

  test "new ignores a search of another user" do
    foreign = users(:two).job_searches.create!(name: "Alheia", source: "indeed")
    get new_job_listing_url(job_search_id: foreign.id)
    assert_response :success
    assert_no_match "Alheia", response.body
  end

  test "create saves a listing through the importer" do
    assert_difference -> { @user.job_listings.count }, 1 do
      post job_listings_url, params: { job_listing: {
        url: "https://pt.indeed.com/viewjob?jk=abc123&utm_source=x", title: "Dev Júnior", company_name: "Beta",
        location: "Porto", source: "", job_search_id: @job_search.id, published_at: "2026-09-20T10:00", description: "Olá"
      } }
    end
    listing = @user.job_listings.order(:id).last
    assert_redirected_to job_listing_url(listing)
    assert_equal "Vaga guardada.", flash[:notice]
    assert_equal "indeed", listing.source
    assert_equal "abc123", listing.external_id
    assert_equal @job_search, listing.job_search
  end

  test "create with a duplicate url redirects to the existing listing" do
    assert_no_difference -> { JobListing.count } do
      post job_listings_url, params: { job_listing: {
        url: "https://linkedin.com/jobs/view/3900000001?trk=public_jobs&utm_campaign=x", title: "Outra vez"
      } }
    end
    assert_redirected_to job_listing_url(@listing)
    assert_equal "Esta vaga já estava guardada.", flash[:notice]
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { JobListing.count } do
      post job_listings_url, params: { job_listing: { url: "abc", title: "" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "create rejects a job search of another user" do
    foreign = users(:two).job_searches.create!(name: "Alheia", source: "indeed")
    assert_no_difference -> { JobListing.count } do
      post job_listings_url, params: { job_listing: { url: "https://acme.pt/99", title: "Dev", job_search_id: foreign.id } }
    end
    assert_response :unprocessable_entity
    assert_no_match "Alheia", response.body
  end

  test "destroy removes the listing but keeps the application" do
    application = create_job_application(@user, job_listing: @listing)
    assert_difference -> { JobListing.count }, -1 do
      delete job_listing_url(@listing)
    end
    assert_redirected_to job_listings_url
    assert_nil application.reload.job_listing_id
    assert AuditLog.exists?(action: "job_listing.destroyed", resource_id: @listing.id)
  end

  test "other users get 404 on someone else's listing" do
    sign_out
    sign_in_as(users(:two))

    get job_listing_url(@listing)
    assert_response :not_found

    assert_no_difference -> { JobListing.count } do
      delete job_listing_url(@listing)
    end
    assert_response :not_found
  end

  test "requires authentication" do
    sign_out
    get job_listings_url
    assert_redirected_to new_session_url
  end
end
