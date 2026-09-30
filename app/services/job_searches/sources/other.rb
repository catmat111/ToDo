module JobSearches
  module Sources
    # Generic fallback: a Google search for job offers ("<query> <location> emprego").
    class Other < Base
      BASE_URL = "https://www.google.com/search".freeze
      # Google's "qdr" (query date range) values.
      RECENCY = { "24h" => "qdr:d", "3d" => "qdr:d3", "week" => "qdr:w", "2weeks" => "qdr:w2", "month" => "qdr:m" }.freeze
      JOB_TYPE_TERMS = {
        "full_time" => "tempo inteiro", "part_time" => "part-time", "contract" => "contrato",
        "temporary" => "temporário", "internship" => "estágio"
      }.freeze
      REMOTE_TERMS = { "yes" => "remoto", "hybrid" => "híbrido", "no" => "presencial" }.freeze

      def label
        "Google"
      end

      private
        def base_url
          BASE_URL
        end

        def params
          {
            "q" => keywords(extra: [ location, *job_type_terms, REMOTE_TERMS[remote], "emprego" ]),
            "tbs" => RECENCY[first_value("recency")]
          }
        end

        def job_type_terms
          values_for("job_type").filter_map { |value| JOB_TYPE_TERMS[value] }
        end
    end
  end
end
