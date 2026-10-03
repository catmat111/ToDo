module Inbox
  # Reads new emails from the chosen Gmail label and turns each into an EmailMessage
  # suggestion (outcome + probable application). Never changes an application itself.
  #
  #   Inbox::Sync.call(connection)  # => number of new suggestions
  class Sync
    FIRST_SYNC_WINDOW = 120.days

    def self.call(connection, client: GmailClient.new)
      new(connection, client:).call
    end

    def initialize(connection, client:)
      @connection = connection
      @client = client
      @user = connection.user
    end

    def call
      return 0 unless @connection.active? && @connection.label_chosen?

      token = access_token
      since = @connection.last_synced_at ? @connection.last_synced_at - 1.day : FIRST_SYNC_WINDOW.ago
      known = @user.email_messages.pluck(:external_id).to_set
      created = 0

      @client.message_ids(access_token: token, label_id: @connection.label_id, after: since).each do |id|
        next if known.include?(id)
        created += 1 if import(@client.message(access_token: token, id: id))
      end

      @connection.update!(last_synced_at: Time.current, last_error: nil)
      Inbox::Rematch.call(@user) # earlier emails may now match newly added applications
      notify(created) if created.positive?
      created
    rescue GoogleClient::AuthError
      @connection.mark_error!("Autorização expirada — volta a ligar o Gmail.")
      0
    end

    private
      def access_token
        return @connection.access_token unless @connection.token_expired?
        tokens = @client.refresh(refresh_token: @connection.refresh_token)
        @connection.update!(access_token: tokens.access_token, expires_at: tokens.expires_at)
        tokens.access_token
      end

      def import(mail)
        mail = mail.merge(text: Inbox::Text.clean(mail[:text]))
        outcome = Inbox::Classifier.call(subject: mail[:subject], text: mail[:text])
        application = Inbox::Matcher.call(user: @user, from_email: mail[:from_email], subject: mail[:subject], text: mail[:text])
        @user.email_messages.create!(
          external_id: mail[:id], from_name: mail[:from_name], from_email: mail[:from_email],
          subject: mail[:subject].to_s.truncate(250), excerpt: mail[:text].to_s.squish.truncate(600),
          received_at: mail[:received_at], outcome: outcome, job_application: application
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        nil
      end

      def notify(count)
        @user.notifications.create!(
          notification_type: "application",
          title: count == 1 ? "1 resposta nova de uma empresa para rever" : "#{count} respostas novas de empresas para rever",
          body: "Confirma a que candidatura pertencem e o que dizem."
        )
      end
  end
end
