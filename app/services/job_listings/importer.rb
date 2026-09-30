module JobListings
  # Single entry point for saving job listings, whether typed by the user or returned
  # by a future official API adapter. Never duplicates a listing: the same job
  # (same normalized URL, or same source + external id) collapses to one row per user.
  #
  #   result = JobListings::Importer.call(user: Current.user, attributes: { url:, title: }, job_search: search)
  #   result.listing   # saved (or existing) JobListing; unsaved with errors when invalid
  #   result.created?  # true only when a new row was inserted
  #   result.duplicate?
  class Importer
    ATTRIBUTES = %i[url title company_name location source external_id description published_at job_search_id].freeze

    Result = Data.define(:listing, :created) do
      def created? = created
      def duplicate? = !created && listing.persisted?
      def success? = listing.persisted?
    end

    def self.call(user:, attributes:, job_search: nil)
      new(user:, attributes:, job_search:).call
    end

    # Imports a batch (e.g. the results of one execution) and returns one Result per item.
    def self.call_many(user:, items:, job_search: nil)
      items.map { |attributes| call(user:, attributes:, job_search:) }
    end

    def initialize(user:, attributes:, job_search: nil)
      @user = user
      @attributes = attributes.to_h.symbolize_keys.slice(*ATTRIBUTES)
      @job_search = job_search
    end

    def call
      listing = @user.job_listings.new(listing_attributes)
      return Result.new(listing:, created: false) unless job_search_allowed?(listing)

      if (existing = find_existing(listing))
        backfill(existing, listing)
        return Result.new(listing: existing, created: false)
      end

      if listing.save
        AuditLog.record("job_listing.created", resource: listing, user: @user,
                        source: listing.source, job_search_id: listing.job_search_id)
        Result.new(listing:, created: true)
      else
        Result.new(listing:, created: false)
      end
    rescue ActiveRecord::RecordNotUnique
      # Another request saved the same job in the meantime.
      Result.new(listing: find_existing(listing) || listing, created: false)
    end

    private
      def listing_attributes
        attrs = @attributes.except(:job_search_id)
        search = resolved_job_search
        attrs[:job_search] = search if search
        attrs[:source] = attrs[:source].presence || detected_source(attrs[:url]) || search&.source || "other"
        attrs[:external_id] = attrs[:external_id].presence ||
          JobSearches::Sources.external_id_from(attrs[:url], source: attrs[:source])
        attrs
      end

      # An explicit job_search wins; otherwise job_search_id must belong to the user.
      def resolved_job_search
        return @resolved_job_search if defined?(@resolved_job_search)
        @resolved_job_search = @job_search || lookup_job_search
      end

      def lookup_job_search
        id = @attributes[:job_search_id]
        id.present? ? @user.job_searches.find_by(id: id) : nil
      end

      def job_search_allowed?(listing)
        if @attributes[:job_search_id].present? && resolved_job_search.nil?
          listing.errors.add(:job_search, "não foi encontrada")
          return false
        end
        true
      end

      def detected_source(url)
        return if url.blank?
        source = JobSearches::Sources.detect(url)
        source unless source == "other"
      end

      def find_existing(listing)
        return if listing.url.blank?
        scope = @user.job_listings
        scope.find_by(normalized_url: JobListing.normalize_url(listing.url)) ||
          (listing.external_id.present? && scope.find_by(source: listing.source, external_id: listing.external_id)) ||
          nil
      end

      # Fills blanks on the existing row without overwriting what the user already has.
      def backfill(existing, incoming)
        fields = %i[company_name location description published_at external_id job_search_id]
        changes = fields.each_with_object({}) do |field, memo|
          memo[field] = incoming[field] if existing[field].blank? && incoming[field].present?
        end
        changes.delete(:external_id) if changes[:external_id] && external_id_taken?(existing, changes[:external_id])
        existing.update(changes) if changes.any?
      end

      def external_id_taken?(existing, external_id)
        @user.job_listings.where(source: existing.source, external_id: external_id).where.not(id: existing.id).exists?
      end
  end
end
