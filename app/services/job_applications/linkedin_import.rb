require "csv"

module JobApplications
  # Imports the "Job Applications.csv" from LinkedIn's official data export
  # (Settings → Data privacy → Get a copy of your data → Job applications).
  # No scraping and no LinkedIn credentials: the user downloads the file herself.
  #
  #   JobApplications::LinkedinImport.call(user: Current.user, io: params[:file])
  #   # => #<Summary created=12 updated=1 skipped=30 failed=0 errors=[]>
  #
  # Re-importing is safe: listings are deduplicated by URL / LinkedIn job id and an
  # application already marked as sent is skipped.
  class LinkedinImport
    Summary = Struct.new(:created, :updated, :skipped, :failed, :errors, keyword_init: true) do
      def total = created + updated + skipped + failed
    end

    # Header names used by LinkedIn (English and Portuguese exports).
    COLUMNS = {
      date: [ "Application Date", "Data da candidatura" ],
      email: [ "Contact Email", "E-mail de contato", "Email de contacto" ],
      phone: [ "Contact Phone Number", "Telefone de contato", "Telefone de contacto" ],
      company: [ "Company Name", "Nome da empresa" ],
      title: [ "Job Title", "Cargo" ],
      url: [ "Job Url", "Job URL", "URL da vaga" ],
      resume: [ "Resume Name", "Nome do currículo" ]
    }.freeze
    MAX_ROWS = 2000

    def self.call(...)
      new(...).call
    end

    def initialize(user:, io:)
      @user = user
      @io = io
      @summary = Summary.new(created: 0, updated: 0, skipped: 0, failed: 0, errors: [])
    end

    def call
      rows = CSV.parse(read_text, headers: true, skip_blanks: true)
      raise ArgumentError, "o ficheiro não parece ser o «Job Applications.csv» do LinkedIn" unless linkedin_file?(rows.headers)

      rows.first(MAX_ROWS).each_with_index { |row, i| import_row(row, i + 2) }
      Inbox::Rematch.call(@user) # replies already read can now find their application
      AuditLog.record("job_application.linkedin_import", user: @user, **@summary.to_h.except(:errors))
      @summary
    end

    private
      def read_text
        text = @io.read.to_s.force_encoding("UTF-8")
        text = text.encode("UTF-8", "ISO-8859-1") unless text.valid_encoding?
        text.delete_prefix("﻿")
      end

      def linkedin_file?(headers)
        headers = headers.compact.map(&:strip)
        (COLUMNS[:title] & headers).any? && (COLUMNS[:company] & headers).any?
      end

      def value(row, key)
        COLUMNS[key].each { |name| (v = row[name]).present? && (return v.strip) }
        nil
      end

      def import_row(row, line)
        title = value(row, :title)
        return fail!(line, "sem cargo") if title.blank?

        applied_at = parse_date(value(row, :date)) || Time.current
        listing = import_listing(row, title)
        existing = listing && @user.job_applications.find_by(job_listing: listing)

        if existing && existing.status != "saved"
          @summary.skipped += 1
        elsif existing
          mark_applied(existing, applied_at)
          @summary.updated += 1
        else
          create_application(row, title, listing, applied_at)
          @summary.created += 1
        end
      rescue StandardError => e
        fail!(line, e.message)
      end

      def import_listing(row, title)
        url = value(row, :url)
        return nil unless url&.match?(%r{\Ahttps?://}i)

        result = JobListings::Importer.call(user: @user, attributes: {
          url: url, title: title, company_name: value(row, :company), source: "linkedin"
        })
        result.listing if result.success?
      end

      def create_application(row, title, listing, applied_at)
        notes = [ "Importada do LinkedIn.", ("CV enviado: #{value(row, :resume)}" if value(row, :resume)) ].compact.join("\n")
        result = JobApplications::Create.call(
          user: @user, occurred_at: applied_at,
          params: { job_listing_id: listing&.id, title: title, company_name: value(row, :company),
                    notes: notes, contact_id: recruiter(row)&.id }
        )
        raise result.error.to_s unless result.success?
        mark_applied(result.job_application, applied_at)
      end

      def mark_applied(application, applied_at)
        result = JobApplications::Transition.call(application, to: "applied", occurred_at: applied_at,
                                                               notes: "Candidatura feita no LinkedIn")
        raise result.error.to_s unless result.success?
      end

      # The recruiter LinkedIn lists for the application, as a Contact (reused by email).
      def recruiter(row)
        email = value(row, :email)&.downcase
        return nil if email.blank?

        @user.contacts.find_by(email: email) ||
          @user.contacts.create(name: email.split("@").first.tr("._", " ").titleize, email: email,
                                phone: value(row, :phone), role: "Recrutador(a)", company: company_for(row))
      end

      def company_for(row)
        name = value(row, :company)
        return nil if name.blank?
        @user.companies.named(name).first || @user.companies.create(name: name)
      end

      # LinkedIn writes dates like "10/1/26, 4:31 PM"; fall back to a generic parse.
      def parse_date(text)
        return nil if text.blank?
        Time.zone.strptime(text, "%m/%d/%y, %I:%M %p")
      rescue ArgumentError
        Time.zone.parse(text) rescue nil
      end

      def fail!(line, message)
        @summary.failed += 1
        @summary.errors << "Linha #{line}: #{message}" if @summary.errors.size < 20
      end
  end
end
