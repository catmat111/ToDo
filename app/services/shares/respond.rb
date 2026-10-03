module Shares
  # The recipient accepts (a copy is created in their account) or declines a share.
  #
  #   Shares::Respond.call(share, accept: true)  # => Result(success, message, copy)
  class Respond
    Result = Data.define(:success, :message, :copy) do
      def success? = success
    end

    def self.call(...)
      new(...).call
    end

    def initialize(share, accept:)
      @share = share
      @accept = accept
      @recipient = share.recipient
    end

    def call
      return Result.new(success: false, message: "Esta partilha já foi respondida.", copy: nil) unless @share.pending?
      return decline unless @accept

      original = @share.shareable
      return Result.new(success: false, message: "O item original já não existe.", copy: nil) if original.nil?

      copy = nil
      Share.transaction do
        copy = build_copy(original)
        @share.update!(status: "accepted", responded_at: Time.current, copy: copy)
        notify_sender("aceitou")
      end
      AuditLog.record("share.accepted", resource: @share, user: @recipient)
      Result.new(success: true, message: "Partilha aceite — já está na tua conta.", copy: copy)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, message: e.record.errors.full_messages.to_sentence, copy: nil)
    end

    private
      def decline
        Share.transaction do
          @share.update!(status: "declined", responded_at: Time.current)
          notify_sender("recusou")
        end
        AuditLog.record("share.declined", resource: @share, user: @recipient)
        Result.new(success: true, message: "Partilha recusada.", copy: nil)
      end

      def build_copy(original)
        case original
        when Task then copy_task(original)
        when JobListing then application_from_listing(original)
        when JobApplication then copy_application(original)
        end
      end

      # The task and its direct subtasks; tags/reminders are personal and not copied.
      def copy_task(task)
        copy = @recipient.tasks.create!(task_attributes(task))
        task.subtasks.each { |sub| @recipient.tasks.create!(task_attributes(sub).merge(parent_task: copy)) }
        copy
      end

      def task_attributes(task)
        task.slice(:title, :description, :task_type, :priority, :starts_at, :due_at)
      end

      def application_from_listing(listing)
        own_listing = JobListings::Importer.call(
          user: @recipient,
          attributes: listing.slice(:url, :title, :company_name, :location, :source, :description, :published_at, :external_id)
        ).listing
        raise ActiveRecord::RecordInvalid, own_listing unless own_listing.persisted?

        result = JobApplications::Create.call(user: @recipient, params: { job_listing_id: own_listing.id })
        raise ActiveRecord::RecordInvalid, result.job_application unless result.success?
        result.job_application
      end

      # Only the job itself is shared; the sender's status, notes and history stay private.
      def copy_application(application)
        return application_from_listing(application.job_listing) if application.job_listing

        result = JobApplications::Create.call(
          user: @recipient, params: { title: application.title, company_name: application.company_name }
        )
        raise ActiveRecord::RecordInvalid, result.job_application unless result.success?
        result.job_application
      end

      def notify_sender(verb)
        @share.sender.notifications.create!(
          notification_type: "share", notifiable: @share,
          title: "#{@recipient.name} #{verb} a tua partilha: #{@share.title}"
        )
      end
  end
end
