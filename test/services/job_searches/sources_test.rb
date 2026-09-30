require "test_helper"

class JobSearches::SourcesTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  def search(source, query: "ruby on rails", filters: [])
    @user.job_searches.create!(name: "Pesquisa #{source}", source: source, query: query).tap do |job_search|
      filters.each { |key, value, operator| job_search.job_filters.create!(key: key, value: value, operator: operator || "equals") }
      job_search.job_filters.reset
    end
  end

  def query_params(url)
    URI.decode_www_form(URI.parse(url).query.to_s).to_h
  end

  test "picks the adapter by source" do
    assert_instance_of JobSearches::Sources::Linkedin, JobSearches::Sources.for(search("linkedin"))
    assert_instance_of JobSearches::Sources::Indeed, JobSearches::Sources.for(search("indeed"))
    assert_instance_of JobSearches::Sources::Other, JobSearches::Sources.for(search("other"))
    assert_equal "LinkedIn", JobSearches::Sources.for(search("linkedin")).label
    assert_equal "Indeed", JobSearches::Sources.for(search("indeed")).label
  end

  test "linkedin url with every filter" do
    job_search = search("linkedin", filters: [
      [ "location", "Lisboa, Portugal" ], [ "recency", "week" ], [ "job_type", "full_time" ],
      [ "job_type", "contract" ], [ "experience", "entry" ], [ "experience", "associate" ], [ "remote", "yes" ],
      [ "keywords", "hotwire", "contains" ], [ "keywords", "estágio", "excludes" ]
    ])
    url = JobSearches::Sources.for(job_search).url

    assert url.start_with?("https://www.linkedin.com/jobs/search/?")
    params = query_params(url)
    assert_equal "ruby on rails hotwire NOT estágio", params["keywords"]
    assert_equal "Lisboa, Portugal", params["location"]
    assert_equal "r604800", params["f_TPR"]
    assert_equal "F,C", params["f_JT"]
    assert_equal "2", params["f_WT"]
    assert_equal "2,3", params["f_E"]
    assert_includes url, "keywords=ruby+on+rails+hotwire+NOT+est%C3%A1gio"
    assert_includes url, "location=Lisboa%2C+Portugal"
  end

  test "linkedin recency and job type mappings" do
    { "24h" => "r86400", "week" => "r604800", "month" => "r2592000" }.each do |value, code|
      assert_equal code, query_params(search("linkedin", filters: [ [ "recency", value ] ]).search_url)["f_TPR"]
    end
    { "full_time" => "F", "part_time" => "P", "contract" => "C", "temporary" => "T", "internship" => "I" }.each do |value, code|
      assert_equal code, query_params(search("linkedin", filters: [ [ "job_type", value ] ]).search_url)["f_JT"]
    end
    { "internship" => "1", "entry" => "2", "associate" => "3", "mid_senior" => "4", "director" => "5", "executive" => "6" }.each do |value, code|
      assert_equal code, query_params(search("linkedin", filters: [ [ "experience", value ] ]).search_url)["f_E"]
    end
  end

  test "linkedin omits empty params" do
    url = search("linkedin", query: nil).search_url
    assert_equal "https://www.linkedin.com/jobs/search/", url
  end

  test "excluded multi-word terms are quoted and exact keywords use quotes" do
    job_search = search("linkedin", query: "developer", filters: [
      [ "keywords", "ruby on rails", "equals" ], [ "keywords", "call center", "excludes" ], [ "location", "Porto", "excludes" ]
    ])
    assert_equal %(developer "ruby on rails" NOT "call center" NOT Porto), query_params(job_search.search_url)["keywords"]
    assert_nil query_params(job_search.search_url)["location"]
  end

  test "indeed url with every filter" do
    job_search = search("indeed", filters: [
      [ "location", "Porto" ], [ "recency", "3d" ], [ "job_type", "part_time" ], [ "radius", "25" ],
      [ "remote", "yes" ], [ "keywords", "júnior", "excludes" ]
    ])
    url = job_search.search_url

    assert url.start_with?("https://pt.indeed.com/jobs?")
    params = query_params(url)
    assert_equal "ruby on rails NOT júnior", params["q"]
    assert_equal "Porto", params["l"]
    assert_equal "3", params["fromage"]
    assert_equal "parttime", params["jt"]
    assert_equal "25", params["radius"]
    assert_equal JobSearches::Sources::Indeed::REMOTE_JOB_ID, params["remotejob"]
  end

  test "indeed recency and job type mappings" do
    { "24h" => "1", "3d" => "3", "week" => "7", "2weeks" => "14", "month" => "30" }.each do |value, days|
      assert_equal days, query_params(search("indeed", filters: [ [ "recency", value ] ]).search_url)["fromage"]
    end
    { "full_time" => "fulltime", "part_time" => "parttime", "contract" => "contract",
      "temporary" => "temporary", "internship" => "internship" }.each do |value, code|
      assert_equal code, query_params(search("indeed", filters: [ [ "job_type", value ] ]).search_url)["jt"]
    end
  end

  test "indeed hybrid goes into the query" do
    params = query_params(search("indeed", filters: [ [ "remote", "hybrid" ] ]).search_url)
    assert_equal "ruby on rails híbrido", params["q"]
    assert_nil params["remotejob"]
  end

  test "other builds a Google search for jobs" do
    job_search = search("other", query: "enfermeiro", filters: [
      [ "location", "Coimbra" ], [ "recency", "month" ], [ "remote", "yes" ], [ "keywords", "noturno", "excludes" ]
    ])
    url = job_search.search_url

    assert url.start_with?("https://www.google.com/search?")
    params = query_params(url)
    assert_equal "enfermeiro Coimbra remoto emprego NOT noturno", params["q"]
    assert_equal "qdr:m", params["tbs"]
  end

  test "filters not supported by the source are ignored" do
    job_search = search("indeed", filters: [ [ "radius", "50" ] ])
    job_search.update!(source: "linkedin")
    assert_not_includes job_search.reload.search_url, "50"
  end

  test "unsaved filters are not part of the url" do
    job_search = search("linkedin", filters: [ [ "location", "Braga" ] ])
    job_search.job_filters.load
    JobFilter.new(job_search: job_search, key: "location", value: "Faro")
    assert_equal "Braga", query_params(job_search.search_url)["location"]
  end

  test "detect source and external ids from urls" do
    assert_equal "linkedin", JobSearches::Sources.detect("https://www.linkedin.com/jobs/view/3912345678/")
    assert_equal "linkedin", JobSearches::Sources.detect("https://pt.linkedin.com/jobs/view/dev-at-acme-3912345678")
    assert_equal "indeed", JobSearches::Sources.detect("https://pt.indeed.com/viewjob?jk=abc123")
    assert_equal "indeed", JobSearches::Sources.detect("https://www.indeed.co.uk/viewjob?jk=abc123")
    assert_equal "other", JobSearches::Sources.detect("https://notlinkedin.com/jobs/view/3912345678")
    assert_equal "other", JobSearches::Sources.detect("not a url")

    assert_equal "3912345678", JobSearches::Sources.external_id_from("https://www.linkedin.com/jobs/view/3912345678/?trk=x")
    assert_equal "3912345678", JobSearches::Sources.external_id_from("https://pt.linkedin.com/jobs/view/dev-rails-at-acme-3912345678")
    assert_equal "3912345678", JobSearches::Sources.external_id_from("https://www.linkedin.com/jobs/search/?currentJobId=3912345678")
    assert_equal "abc123", JobSearches::Sources.external_id_from("https://pt.indeed.com/viewjob?jk=abc123&from=serp")
    assert_nil JobSearches::Sources.external_id_from("https://acme.pt/careers/42")
  end
end
