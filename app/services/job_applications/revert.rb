module JobApplications
  # Undoes the last status change (a mistake, or "the interview didn't happen"): goes back
  # to JobApplication#previous_status and removes that step from the history. Tasks the
  # change created (follow-up, interview) are kept; delete them by hand if not needed.
  #
  #   JobApplications::Revert.call(application)
  class Revert
    def self.call(...)
      new(...).call
    end

    def initialize(job_application)
      @job_application = job_application
    end

    def call
      from = job_application.status
      to = job_application.previous_status
      return Result.new(success: false, job_application: job_application, error: "Não há nenhuma mudança de estado para desfazer.") unless to

      ActiveRecord::Base.transaction do
        latest = job_application.status_history.first
        latest.destroy! if latest&.event_type == from # the history may already lack it
        job_application.status = to
        job_application.applied_at = nil if to == "saved"
        job_application.save!
      end

      AuditLog.record("job_application.status_reverted", resource: job_application, user: job_application.user, from: from, to: to)
      Result.new(success: true, job_application: job_application, tasks: [])
    rescue ActiveRecord::RecordInvalid => e
      job_application.reload
      Result.new(success: false, job_application: job_application, error: e.record.errors.full_messages.to_sentence)
    end

    private
      attr_reader :job_application
  end
end
