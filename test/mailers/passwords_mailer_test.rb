require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "reset" do
    user = users(:one)
    mail = PasswordsMailer.reset(user)

    assert_equal "Redefinir a tua password do Tu Do", mail.subject
    assert_equal [ "one@example.com" ], mail.to

    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_match "Olá, Ana!", body
      assert_match %r{http://example\.com/passwords/[^/\s"]+/edit}, body
      assert_match "O link expira dentro de", body
      assert_match "podes ignorar este email", body
    end
  end
end
