require "test_helper"

class JobFiltersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @job_search = @user.job_searches.create!(name: "Rails", source: "linkedin", query: "rails")
    @filter = @job_search.job_filters.create!(key: "location", value: "Lisboa")
    sign_in_as(@user)
  end

  test "create adds a filter" do
    assert_difference -> { @job_search.job_filters.count }, 1 do
      post job_search_job_filters_url(@job_search), params: { job_filter: { key: "recency", operator: "equals", value: "24h" } }
    end
    assert_redirected_to job_search_url(@job_search, anchor: "filtros")
    assert_equal "Filtro «Recência» adicionado.", flash[:notice]
    assert AuditLog.exists?(action: "job_search.filter_added", resource_id: @job_search.id)
  end

  test "create accepts friendly spellings" do
    post job_search_job_filters_url(@job_search), params: { job_filter: { key: "job_type", operator: "equals", value: "Part-time" } }
    assert_equal "part_time", @job_search.job_filters.order(:id).last.value
  end

  test "create rejects keys the source does not support" do
    assert_no_difference -> { JobFilter.count } do
      post job_search_job_filters_url(@job_search), params: { job_filter: { key: "radius", operator: "equals", value: "25" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_select "h1", "Rails"
  end

  test "create rejects excludes on structured keys" do
    assert_no_difference -> { JobFilter.count } do
      post job_search_job_filters_url(@job_search), params: { job_filter: { key: "job_type", operator: "excludes", value: "internship" } }
    end
    assert_response :unprocessable_entity
  end

  test "create excludes keyword" do
    post job_search_job_filters_url(@job_search), params: { job_filter: { key: "keywords", operator: "excludes", value: "estágio" } }
    assert_includes URI.decode_www_form_component(@job_search.reload.search_url), "NOT estágio"
  end

  test "update changes a filter" do
    patch job_search_job_filter_url(@job_search, @filter), params: { job_filter: { key: "location", operator: "contains", value: "Porto" } }
    assert_redirected_to job_search_url(@job_search, anchor: "filtros")
    assert_equal [ "Porto", "contains" ], @filter.reload.values_at(:value, :operator)
  end

  test "update with invalid data re-renders the search page" do
    patch job_search_job_filter_url(@job_search, @filter), params: { job_filter: { key: "location", value: "" } }
    assert_response :unprocessable_entity
    assert_select "details.job-filter-edit[open]"
    assert_equal "Lisboa", @filter.reload.value
  end

  test "destroy removes a filter" do
    assert_difference -> { JobFilter.count }, -1 do
      delete job_search_job_filter_url(@job_search, @filter)
    end
    assert_redirected_to job_search_url(@job_search, anchor: "filtros")
  end

  test "other users get 404 on filters of someone else's search" do
    sign_out
    sign_in_as(users(:two))

    assert_no_difference -> { JobFilter.count } do
      post job_search_job_filters_url(@job_search), params: { job_filter: { key: "recency", value: "24h" } }
    end
    assert_response :not_found

    patch job_search_job_filter_url(@job_search, @filter), params: { job_filter: { value: "Porto" } }
    assert_response :not_found

    assert_no_difference -> { JobFilter.count } do
      delete job_search_job_filter_url(@job_search, @filter)
    end
    assert_response :not_found
    assert_equal "Lisboa", @filter.reload.value
  end

  test "a filter cannot be reached through another search" do
    other_search = @user.job_searches.create!(name: "Outra", source: "indeed")
    delete job_search_job_filter_url(other_search, @filter)
    assert_response :not_found

    foreign_search = users(:two).job_searches.create!(name: "Alheia", source: "indeed")
    foreign_filter = foreign_search.job_filters.create!(key: "location", value: "Faro")
    patch job_search_job_filter_url(@job_search, foreign_filter), params: { job_filter: { value: "Porto" } }
    assert_response :not_found
    assert_equal "Faro", foreign_filter.reload.value
  end
end
