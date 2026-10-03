module Shares
  # Sends one of the sender's tasks / listings / applications to another user.
  #
  #   Shares::Create.call(sender: Current.user, shareable: task, email: "ana@x.pt", message: "Vês isto?")
  #
  # The result message is the same whether or not the email has an account, so the
  # form can't be used to find out who uses the app.
  class Create
    Result = Data.define(:success, :message, :share) do
      def success? = success
    end
    SENT_MESSAGE = "Se existir uma conta com esse email, a partilha foi enviada.".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(sender:, shareable:, email:, message: nil)
      @sender = sender
      @shareable = shareable
      @email = email.to_s.strip.downcase
      @message = message
    end

    def call
      return failure("Indica o email da pessoa.") if @email.blank?
      return failure("Não podes partilhar contigo.") if @email == @sender.email_address

      recipient = User.find_by(email_address: @email)
      return Result.new(success: true, message: SENT_MESSAGE, share: nil) if recipient.nil?

      share = nil
      Share.transaction do
        share = Share.create!(sender: @sender, recipient: recipient, shareable: @shareable,
                              title: title, message: @message)
        recipient.notifications.create!(
          notification_type: "share", notifiable: share,
          title: "#{@sender.name} partilhou contigo: #{title}",
          body: [ "#{share.kind_label} para aceitar ou recusar.", share.message ].compact.join(" ")
        )
      end
      AuditLog.record("share.sent", resource: share, user: @sender, kind: share.shareable_type)
      Result.new(success: true, message: SENT_MESSAGE, share: share)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private
      def title
        @shareable.title.to_s.truncate(200)
      end

      def failure(message)
        Result.new(success: false, message: message, share: nil)
      end
  end
end
