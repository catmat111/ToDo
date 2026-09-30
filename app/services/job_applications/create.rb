module JobApplications
  # Creates an application manually or from one of the user's job listings (plan §16, flow D).
  #
  #   JobApplications::Create.call(user: Current.user, params: { job_listing_id: 3 })
  #
  # - The listing is looked up through the user, so someone else's id raises RecordNotFound (404).
  # - Title/company are copied from the listing when not given; they are a snapshot that survives
  #   the listing being deleted later (plan §23).
  # - A listing never gets two applications: the existing one is returned (created: false).
  # - Every new application starts as "saved" with a matching "saved" history event.
  class Create
    PERMITTED = %i[title company_name notes job_listing_id].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(user:, params:, occurred_at: Time.current)
      @user = user
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      @occurred_at = occurred_at
    end

    def call
      listing = find_listing
      if listing && (existing = user.job_applications.find_by(job_listing: listing))
        return Result.new(success: true, job_application: existing, created: false)
      end

      application = build(listing)
      event = nil
      ActiveRecord::Base.transaction do
        application.save!
        event = application.job_application_events.create!(event_type: "saved", occurred_at: occurred_at)
      end

      AuditLog.record("job_application.created", resource: application, user: user,
                      job_listing_id: listing&.id, source: listing ? "listing" : "manual")
      Result.new(success: true, job_application: application, created: true, event: event)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, job_application: application, created: false,
                 error: e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      # Two concurrent requests for the same listing: the other one won, use it.
      existing = user.job_applications.find_by(job_listing: listing)
      Result.new(success: existing.present?, job_application: existing || application, created: false,
                 error: ("Não foi possível criar a candidatura." unless existing))
    end

    private
      attr_reader :user, :params, :occurred_at

      def find_listing
        id = params[:job_listing_id]
        id.present? ? user.job_listings.find(id) : nil
      end

      def build(listing)
        user.job_applications.new(
          job_listing: listing,
          title: params[:title].presence || listing&.title,
          company_name: params[:company_name].presence || listing&.company_name,
          notes: params[:notes].presence,
          status: "saved"
        )
      end
  end
end
