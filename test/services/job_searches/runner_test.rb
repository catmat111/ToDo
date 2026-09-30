require "test_helper"

class JobSearches::RunnerTest < ActiveSupport::TestCase
  setup do
    @job_search = users(:one).job_searches.create!(name: "Rails", source: "linkedin", query: "rails")
    @job_search.job_filters.create!(key: "location", value: "Lisboa")
  end

  test "returns the external url, records the run and audits it" do
    freeze_time do
      url = nil
      assert_difference -> { AuditLog.where(action: "job_search.run").count }, 1 do
        url = JobSearches::Runner.call(@job_search)
      end

      assert_equal @job_search.search_url, url
      assert_includes url, "location=Lisboa"
      assert_equal Time.current, @job_search.reload.last_run_at
    end

    log = AuditLog.where(action: "job_search.run").last
    assert_equal users(:one), log.user
    assert_equal [ "JobSearch", @job_search.id ], [ log.resource_type, log.resource_id ]
    assert_equal "linkedin", log.metadata["source"]
  end
end
