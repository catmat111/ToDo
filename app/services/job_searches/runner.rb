module JobSearches
  # Runs a saved search: builds the external URL with every filter applied, records
  # when it was run and returns the URL. No scraping and no external credentials —
  # the user opens the site (and signs in there, if needed) in their own browser.
  #
  #   url = JobSearches::Runner.call(job_search)
  #   url = JobSearches::Runner.call(job_search, app: true) # linkedin:// link for the LinkedIn app
  class Runner
    def self.call(job_search, app: false)
      new(job_search, app: app).call
    end

    def initialize(job_search, app: false)
      @job_search = job_search
      @app = app
    end

    def call
      adapter = Sources.for(@job_search)
      url = @app && adapter.respond_to?(:app_url) ? adapter.app_url : adapter.url

      @job_search.update_columns(last_run_at: Time.current, updated_at: Time.current)
      AuditLog.record("job_search.run", resource: @job_search, user: @job_search.user,
                      source: @job_search.source, filters_count: @job_search.job_filters.size)
      url
    end
  end
end
