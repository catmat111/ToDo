module JobSearches
  module Sources
    # https://www.linkedin.com/jobs/search/?keywords=...&location=...&f_TPR=r604800&f_JT=F&f_WT=2&f_E=2
    class Linkedin < Base
      BASE_URL = "https://www.linkedin.com/jobs/search/".freeze
      RECENCY = {
        "24h" => "r86400", "3d" => "r259200", "week" => "r604800", "2weeks" => "r1209600", "month" => "r2592000"
      }.freeze
      JOB_TYPES = { "full_time" => "F", "part_time" => "P", "contract" => "C", "temporary" => "T", "internship" => "I" }.freeze
      EXPERIENCE = {
        "internship" => "1", "entry" => "2", "associate" => "3", "mid_senior" => "4", "director" => "5", "executive" => "6"
      }.freeze
      WORKPLACE = { "no" => "1", "yes" => "2", "hybrid" => "3" }.freeze

      def self.host_pattern
        /(\A|\.)linkedin\.com\z/
      end

      # /jobs/view/1234567890, /jobs/view/some-title-at-acme-1234567890 or ?currentJobId=1234567890
      def self.external_id_from(url)
        uri = URI.parse(url.to_s.strip)
        uri.path.to_s[%r{/jobs/view/(?:[^/]*?-)?(\d{5,})}, 1] ||
          URI.decode_www_form(uri.query.to_s).to_h["currentJobId"].to_s[/\A\d+\z/]
      rescue URI::InvalidURIError, ArgumentError
        nil
      end

      def label
        "LinkedIn"
      end

      private
        def base_url
          BASE_URL
        end

        def params
          {
            "keywords" => keywords,
            "location" => location,
            "f_TPR" => RECENCY[first_value("recency")],
            "f_JT" => codes(JOB_TYPES, "job_type"),
            "f_WT" => WORKPLACE[remote],
            "f_E" => codes(EXPERIENCE, "experience")
          }
        end

        # LinkedIn accepts several values separated by commas (e.g. f_JT=F,P).
        def codes(mapping, key)
          values_for(key).filter_map { |value| mapping[value] }.uniq.join(",").presence
        end
    end
  end
end
