module JobSearches
  module Sources
    # https://www.itjobs.pt/emprego?q=...&location=14&type=1&contract=2&work_model=1&sort=date
    class Itjobs < Base
      BASE_URL = "https://www.itjobs.pt/emprego".freeze
      # ITjobs filters locations by district id, so only districts we know the id of are mapped;
      # any other location is added to the search text instead.
      LOCATIONS = { "braga" => "4", "coimbra" => "8", "lisboa" => "14", "porto" => "18" }.freeze
      WORK_MODEL = { "no" => "0", "yes" => "1", "hybrid" => "2" }.freeze
      # "type" = working hours; "contract" = contract kind (1 = a termo).
      HOURS = { "full_time" => "1", "part_time" => "2" }.freeze
      CONTRACT = { "contract" => "1", "temporary" => "1" }.freeze

      def self.host_pattern
        /(\A|\.)itjobs\.pt\z/
      end

      # /oferta/518173/devops-engineer
      def self.external_id_from(url)
        URI.parse(url.to_s.strip).path.to_s[%r{/oferta/(\d+)}, 1]
      rescue URI::InvalidURIError
        nil
      end

      def label
        "ITjobs"
      end

      private
        def base_url
          BASE_URL
        end

        # ITjobs has no recency filter, so any "recency" filter just sorts by newest first.
        def params
          {
            "q" => keywords(extra: [ (location unless district_id), ("estágio" if internship?) ]),
            "location" => district_id,
            "type" => HOURS[first_value("job_type")],
            "contract" => CONTRACT[first_value("job_type")],
            "work_model" => WORK_MODEL[remote],
            "sort" => ("date" if first_value("recency"))
          }
        end

        def district_id
          LOCATIONS[I18n.transliterate(location.to_s).downcase.strip]
        end

        def internship?
          values_for("job_type").include?("internship")
        end
    end
  end
end
