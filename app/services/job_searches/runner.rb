module JobSearches
  # Runs a saved search: builds the external URL with every filter applied, records
  # when it was run and returns the URL. No scraping and no external credentials —
  # the user opens the site (and signs in there, if needed) in their own browser.
  #
  #   url = JobSearches::Runner.call(job_search)
  class Runner
    def self.call(job_search)
      new(job_search).call
    end

    def initialize(job_search)
      @job_search = job_search
    end

    def call
      adapter = Sources.for(@job_search)
      url = adapter.url

      @job_search.update_columns(last_run_at: Time.current, updated_at: Time.current)
      AuditLog.record("job_search.run", resource: @job_search, user: @job_search.user,
                      source: @job_search.source, filters_count: @job_search.job_filters.size)
      url
    end
  end
end
