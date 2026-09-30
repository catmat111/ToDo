module JobSearches
  # Registry of source adapters. Adapters are the only place that knows each site's
  # URL format; a future official API integration is just a new adapter (plan §11).
  #
  #   adapter = JobSearches::Sources.for(job_search)
  #   adapter.url   # => "https://www.linkedin.com/jobs/search/?keywords=..."
  #   adapter.label # => "LinkedIn"
  module Sources
    def self.adapters
      { "linkedin" => Linkedin, "indeed" => Indeed, "other" => Other }
    end

    def self.for(job_search)
      adapters.fetch(job_search.source.to_s, Other).new(job_search)
    end

    # Which source a job URL comes from ("linkedin", "indeed" or "other").
    def self.detect(url)
      adapters.find { |_, adapter| adapter.handles?(url) }&.first || "other"
    end

    # Site-specific job id found in a URL (e.g. LinkedIn /jobs/view/123), if any.
    def self.external_id_from(url, source: detect(url))
      adapters.fetch(source.to_s, Other).external_id_from(url)
    end
  end
end
