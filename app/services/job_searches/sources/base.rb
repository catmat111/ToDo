module JobSearches
  module Sources
    # Shared logic for turning a JobSearch and its JobFilters into search terms.
    # Subclasses implement #base_url, #params and #label.
    class Base
      attr_reader :job_search

      def self.host_pattern
        nil
      end

      def self.handles?(url)
        host = URI.parse(url.to_s.strip).host.to_s.downcase
        host_pattern.present? && host.match?(host_pattern)
      rescue URI::InvalidURIError
        false
      end

      def self.external_id_from(_url)
        nil
      end

      def initialize(job_search)
        @job_search = job_search
      end

      def label
        raise NotImplementedError
      end

      def url
        query = URI.encode_www_form(params.compact_blank)
        query.empty? ? base_url : "#{base_url}?#{query}"
      end

      private
        def base_url
          raise NotImplementedError
        end

        def params
          raise NotImplementedError
        end

        # Saved filters this source understands, oldest first.
        def filters
          @filters ||= job_search.job_filters
            .select { |filter| filter.persisted? && allowed_keys.include?(filter.key) }
            .sort_by { |filter| filter.id.to_i }
        end

        def allowed_keys
          JobFilter::ALLOWED_KEYS.fetch(job_search.source.to_s, [])
        end

        def values_for(key)
          filters.select { |filter| filter.key == key && !filter.excludes? }.map(&:value).uniq
        end

        def first_value(key)
          values_for(key).first
        end

        # Query text + "keywords" filters + NOT terms for every "excludes" filter.
        def keywords(extra: [])
          included = filters.select { |filter| filter.key == "keywords" && !filter.excludes? }.map do |filter|
            filter.operator == "equals" ? quote(filter.value, always: true) : filter.value
          end
          excluded = filters.select(&:excludes?).map { |filter| "NOT #{quote(filter.value)}" }

          [ job_search.query, *included, *extra, *excluded ].compact_blank.join(" ")
        end

        # "Igual" means the exact phrase; multi-word NOT terms are quoted so they stay together.
        def quote(term, always: false)
          term = term.to_s.delete('"')
          always || term.include?(" ") ? %("#{term}") : term
        end

        def location
          first_value("location")
        end

        def remote
          first_value("remote")
        end
    end
  end
end
