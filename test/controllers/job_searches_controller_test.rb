require "test_helper"

class JobSearchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job_search = @user.job_searches.create!(name: "Rails em Lisboa", source: "linkedin", query: "ruby on rails")
    @job_search.job_filters.create!(key: "location", value: "Lisboa")
    @job_search.job_filters.create!(key: "recency", value: "week")
    sign_in_as(@user)
  end

  test "requires authentication" do
    sign_out
    get job_searches_url
    assert_redirected_to new_session_url
  end

  test "index shows searches as cards with filters and the run button" do
    @user.job_listings.create!(title: "Dev", url: "https://acme.pt/1", job_search: @job_search)
    get job_searches_url

    assert_response :success
    assert_select "h1", "Pesquisas de emprego"
    assert_select ".job-search-card", 1
    assert_select ".job-search-card", text: /Rails em Lisboa/
    assert_select ".job-source", "LinkedIn"
    assert_select ".job-filter-chip", text: "Localização: Lisboa"
    assert_select ".job-filter-chip", text: "Recência: Última semana"
    assert_select "form[action=?][target=_blank][data-turbo=false]", run_job_search_path(@job_search)
    assert_select "a", text: "1 vaga guardada"
  end

  test "index does not show other users' searches" do
    users(:two).job_searches.create!(name: "Pesquisa do Bruno", source: "indeed")
    get job_searches_url
    assert_no_match "Pesquisa do Bruno", response.body
  end

  test "index empty state" do
    @user.job_searches.destroy_all
    get job_searches_url
    assert_select ".empty-state", text: /Ainda não tens pesquisas/
  end

  test "show lists filters, the add form, url preview and listings" do
    @user.job_listings.create!(title: "Programador Rails", url: "https://acme.pt/1", job_search: @job_search)
    get job_search_url(@job_search)

    assert_response :success
    assert_select "h1", "Rails em Lisboa"
    assert_select ".job-filter-list .list__item", 2
    assert_select "select[name='job_filter[key]'] option", minimum: JobFilter::ALLOWED_KEYS["linkedin"].size
    assert_select "select[name='job_filter[key]'] option[value=radius]", 0
    assert_select "select[name='job_filter[operator]'] option", text: "Exclui"
    assert_select "datalist option[value='24h']"
    assert_select "code.job-search-url", text: /linkedin\.com\/jobs\/search/
    assert_select "a", text: "Programador Rails"
    assert_select "a[href=?]", new_job_listing_path(job_search_id: @job_search.id)
  end

  test "new and create" do
    get new_job_search_url
    assert_response :success
    assert_select "input[type=radio][name='job_search[source]']", 4

    assert_difference -> { @user.job_searches.count }, 1 do
      post job_searches_url, params: { job_search: { name: "Indeed Porto", source: "indeed", query: "designer", active: "1" } }
    end
    created = @user.job_searches.order(:id).last
    assert_redirected_to job_search_url(created)
    assert_equal "indeed", created.source
    assert AuditLog.exists?(action: "job_search.created", resource_id: created.id)
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { JobSearch.count } do
      post job_searches_url, params: { job_search: { name: "", source: "linkedin" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "create ignores a user_id param" do
    post job_searches_url, params: { job_search: { name: "X", source: "other", user_id: users(:two).id } }
    assert_equal @user, JobSearch.order(:id).last.user
  end

  test "edit and update" do
    get edit_job_search_url(@job_search)
    assert_response :success

    patch job_search_url(@job_search), params: { job_search: { name: "Rails remoto", query: "rails", active: "0" } }
    assert_redirected_to job_search_url(@job_search)
    @job_search.reload
    assert_equal "Rails remoto", @job_search.name
    assert_not @job_search.active?
    assert_equal "Pesquisa em pausa.", flash[:notice]
  end

  test "toggle from the index returns to the index" do
    patch job_search_url(@job_search), params: { job_search: { active: "0" }, return_to: "index" }
    assert_redirected_to job_searches_url
  end

  test "update with invalid data re-renders edit" do
    patch job_search_url(@job_search), params: { job_search: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "Rails em Lisboa", @job_search.reload.name
  end

  test "destroy keeps listings" do
    listing = @user.job_listings.create!(title: "Dev", url: "https://acme.pt/1", job_search: @job_search)
    assert_difference -> { JobSearch.count } => -1, -> { JobFilter.count } => -2 do
      delete job_search_url(@job_search)
    end
    assert_redirected_to job_searches_url
    assert_nil listing.reload.job_search_id
  end

  test "run asks whether the user has the LinkedIn app before the first LinkedIn search" do
    post run_job_search_url(@job_search)

    assert_response :success
    assert_select "form[action=?]", run_job_search_path(@job_search), count: 2
    assert_nil @user.reload.linkedin_app
    assert_nil @job_search.reload.last_run_at
  end

  test "answering yes remembers it and opens the LinkedIn app" do
    post run_job_search_url(@job_search), params: { linkedin_app: "yes" }

    # Rendered page (not a redirect): a redirect to linkedin:// breaks inside the service worker.
    assert_response :success
    assert_select "meta[http-equiv=refresh][content^=?]", "0;url=linkedin://jobs/search?"
    assert_select "a[href^=?]", "linkedin://jobs/search?", text: "Abrir na app"
    assert_select "a[href^=?]", "https://www.linkedin.com/jobs/search/?", text: "Abrir no browser"
    assert_equal true, @user.reload.linkedin_app
    assert_not_nil @job_search.reload.last_run_at

    post run_job_search_url(@job_search)
    assert_response :success
    assert_select "meta[http-equiv=refresh]"
  end

  test "answering no remembers it and opens the website" do
    post run_job_search_url(@job_search), params: { linkedin_app: "no" }

    assert response.location.start_with?("https://www.linkedin.com/jobs/search/?")
    assert_equal false, @user.reload.linkedin_app

    post run_job_search_url(@job_search)
    assert response.location.start_with?("https://www.linkedin.com/jobs/search/?")
  end

  test "other sources never ask about the LinkedIn app" do
    indeed = @user.job_searches.create!(name: "Indeed", source: "indeed", query: "rails")
    post run_job_search_url(indeed)

    assert_response :see_other
    assert_nil @user.reload.linkedin_app
  end

  test "run redirects to the external url and records the run" do
    @user.update_column(:linkedin_app, false)
    freeze_time do
      post run_job_search_url(@job_search)

      assert_response :see_other
      location = response.location
      assert location.start_with?("https://www.linkedin.com/jobs/search/?")
      params = URI.decode_www_form(URI.parse(location).query).to_h
      assert_equal "ruby on rails", params["keywords"]
      assert_equal "Lisboa", params["location"]
      assert_equal "r604800", params["f_TPR"]
      assert_equal Time.current, @job_search.reload.last_run_at
    end
    assert AuditLog.exists?(action: "job_search.run", resource_id: @job_search.id)
  end

  test "run only accepts POST" do
    get "/job_searches/#{@job_search.id}/run"
    assert_response :not_found
  end

  test "other users get 404 on every member action" do
    sign_out
    sign_in_as(users(:two))

    get job_search_url(@job_search)
    assert_response :not_found
    get edit_job_search_url(@job_search)
    assert_response :not_found
    patch job_search_url(@job_search), params: { job_search: { name: "Roubada" } }
    assert_response :not_found
    post run_job_search_url(@job_search)
    assert_response :not_found
    assert_no_difference -> { JobSearch.count } do
      delete job_search_url(@job_search)
    end
    assert_response :not_found

    @job_search.reload
    assert_equal "Rails em Lisboa", @job_search.name
    assert_nil @job_search.last_run_at
  end
end
