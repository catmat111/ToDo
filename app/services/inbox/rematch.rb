module Inbox
  # Retries the automatic guesses for replies still waiting for review: links the ones
  # with no application (e.g. emails read before the applications were imported) and
  # re-classifies the ones marked "unknown". Runs when the Respostas page opens, after
  # each Gmail sync and after a LinkedIn import. Never touches confirmed/ignored emails.
  #
  #   Inbox::Rematch.call(user)  # => number of emails that got an application
  class Rematch
    def self.call(user)
      linked = 0
      user.email_messages.pending.where(job_application_id: nil).or(user.email_messages.pending.where(outcome: "unknown")).find_each do |email|
        text = Inbox::Text.clean(email.excerpt)
        changes = {}
        changes[:excerpt] = text if text != email.excerpt
        if email.outcome == "unknown"
          outcome = Inbox::Classifier.call(subject: email.subject, text: text)
          changes[:outcome] = outcome if outcome != "unknown"
        end
        if email.job_application_id.nil?
          application = Inbox::Matcher.call(user: user, from_email: email.from_email, subject: email.subject, text: text)
          if application
            changes[:job_application_id] = application.id
            linked += 1
          end
        end
        email.update_columns(changes.merge(updated_at: Time.current)) if changes.any?
      end
      linked
    end
  end
end
