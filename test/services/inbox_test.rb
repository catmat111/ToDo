require "test_helper"

class InboxTest < ActiveSupport::TestCase
  # Stands in for GmailClient: no network.
  class FakeGmail
    def initialize(messages) = @messages = messages
    def message_ids(**) = @messages.keys
    def message(id:, **) = @messages.fetch(id)
    def refresh(**) = GoogleCalendarClient::TokenSet.new(access_token: "new", refresh_token: nil, expires_at: 1.hour.from_now, scope: nil)
  end

  setup do
    @user = users(:one)
    @application = create_job_application(@user, title: "Programadora Júnior", company_name: "ACME", status: "applied")
    @connection = @user.create_mailbox_connection!(access_token: "t", refresh_token: "r", expires_at: 1.hour.from_now,
                                                   label_id: "Label_1", label_name: "Candidaturas")
  end

  def mail(id, subject:, text:, from: "recrutamento@acme.pt")
    { id: id, from_name: "ACME RH", from_email: from, subject: subject, received_at: 1.day.ago, text: text }
  end

  test "classifies typical replies" do
    assert_equal "rejected", Inbox::Classifier.call(subject: "A tua candidatura", text: "Infelizmente decidimos avançar com outros candidatos.")
    assert_equal "interview", Inbox::Classifier.call(subject: "Próxima fase", text: "Gostaríamos de agendar uma entrevista.")
    assert_equal "offer", Inbox::Classifier.call(subject: "Job offer", text: "We are pleased to offer you the role.")
    assert_equal "received", Inbox::Classifier.call(subject: "Obrigado", text: "Recebemos a tua candidatura.")
    assert_equal "unknown", Inbox::Classifier.call(subject: "Newsletter", text: "Novidades da semana")
  end

  test "sync creates suggestions matched to the application, once" do
    gmail = FakeGmail.new("m1" => mail("m1", subject: "Candidatura ACME", text: "Infelizmente não vamos avançar."))

    assert_difference -> { @user.email_messages.count } => 1 do
      Inbox::Sync.call(@connection, client: gmail)
    end
    email = @user.email_messages.last
    assert_equal "rejected", email.outcome
    assert_equal @application, email.job_application
    assert email.pending?
    assert @application.reload.applied?, "nothing changes before the user confirms"

    assert_no_difference -> { @user.email_messages.count } do
      Inbox::Sync.call(@connection.reload, client: gmail)
    end
  end

  test "confirming moves the application and records the email" do
    email = @user.email_messages.create!(external_id: "m2", subject: "Entrevista", from_email: "rh@acme.pt",
                                         outcome: "interview", received_at: 1.day.ago)
    result = Inbox::Confirm.call(email, job_application: @application, outcome: "interview")

    assert result.success?
    assert @application.reload.interview?
    assert email.reload.confirmed?
    assert_match "Entrevista", @application.job_application_events.last.notes
  end

  test "an expired grant marks the connection as error without raising" do
    gmail = FakeGmail.new({})
    def gmail.message_ids(**) = raise(GoogleCalendarClient::AuthError, "invalid_grant")
    Inbox::Sync.call(@connection, client: gmail)
    assert @connection.reload.error?
  end
end
