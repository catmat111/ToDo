module Inbox
  # The user confirms what an email means: the application moves to the matching status
  # (when that transition is allowed) and the email is recorded in its history.
  #
  #   Inbox::Confirm.call(email, job_application: app, outcome: "rejected")
  class Confirm
    Result = Data.define(:success, :message) do
      def success? = success
    end

    def self.call(...)
      new(...).call
    end

    def initialize(email, job_application:, outcome:)
      @email = email
      @application = job_application
      @outcome = outcome.presence_in(EmailMessage::OUTCOMES.keys) || @email.outcome
    end

    def call
      message = nil
      ActiveRecord::Base.transaction do
        # No application chosen (e.g. one not tracked in the app): just mark the email as handled.
        message = @application ? apply_to_application : "Email marcado como tratado (sem candidatura associada)."
        @email.update!(job_application: @application, outcome: @outcome, review_status: "confirmed", reviewed_at: Time.current)
      end
      Result.new(success: true, message: message)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, message: e.record.errors.full_messages.to_sentence)
    end

    private
      def note
        "Email de #{@email.sender}: «#{@email.subject}»"
      end

      def apply_to_application
        new_status = EmailMessage::OUTCOME_STATUS[@outcome]
        occurred_at = @email.received_at || Time.current

        if new_status && @application.can_transition_to?(new_status)
          result = JobApplications::Transition.call(@application, to: new_status, occurred_at: occurred_at, notes: note)
          raise ActiveRecord::RecordInvalid, @application unless result.success?
          "Candidatura atualizada para «#{JobApplication.status_label(new_status)}»."
        else
          @application.job_application_events.create!(event_type: "note", occurred_at: occurred_at, notes: note)
          "Email adicionado ao histórico da candidatura."
        end
      end
  end
end
