module JobSearches
  module Sources
    # https://pt.indeed.com/jobs?q=...&l=...&fromage=7&jt=fulltime&radius=25&remotejob=...
    class Indeed < Base
      BASE_URL = "https://pt.indeed.com/jobs".freeze
      RECENCY = { "24h" => "1", "3d" => "3", "week" => "7", "2weeks" => "14", "month" => "30" }.freeze
      JOB_TYPES = {
        "full_time" => "fulltime", "part_time" => "parttime", "contract" => "contract",
        "temporary" => "temporary", "internship" => "internship"
      }.freeze
      # Value Indeed uses for its "Remoto" filter.
      REMOTE_JOB_ID = "032b3046-06a3-4876-8dfd-474eb5e7ed11".freeze

      def self.host_pattern
        /(\A|\.)indeed\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})\z/
      end

      # ?jk=0123456789abcdef (job page) or ?vjk=... (job opened from the results list)
      def self.external_id_from(url)
        params = URI.decode_www_form(URI.parse(url.to_s.strip).query.to_s).to_h
        (params["jk"] || params["vjk"]).to_s[/\A[a-z0-9]+\z/i]
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      def label
        "Indeed"
      end

      private
        def base_url
          BASE_URL
        end

        def params
          {
            "q" => keywords(extra: remote == "hybrid" ? [ "híbrido" ] : []),
            "l" => location,
            "radius" => (first_value("radius") if location.present?),
            "fromage" => RECENCY[first_value("recency")],
            "jt" => JOB_TYPES[first_value("job_type")],
            "remotejob" => (REMOTE_JOB_ID if remote == "yes")
          }
        end
    end
  end
end
