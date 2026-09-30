require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new" do
    get new_password_path

    assert_response :success
    assert_select "h2", "Recuperar password"
    assert_select "input[type=email][name=email_address]"
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "vais receber instruções"
  end

  test "create normalizes the email address" do
    post passwords_path, params: { email_address: "  ONE@Example.com " }

    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
  end

  test "create for an unknown user redirects with the same message but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "vais receber instruções"
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)

    assert_response :success
    assert_select "h2", "Nova password"
    assert_select "input[type=password][name=password]"
    assert_select "input[type=password][name=password_confirmation]"
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "é inválido ou expirou"
  end

  test "update resets the password, ends every session and audits" do
    @user.sessions.create!
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token),
          params: { password: "nova-password", password_confirmation: "nova-password" }
      assert_redirected_to new_session_path
    end

    assert_empty @user.sessions.reload
    assert @user.authenticate("nova-password")
    assert_equal "user.password_reset", AuditLog.order(:id).last.action
    follow_redirect!
    assert_notice "A tua password foi redefinida"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "nova-password", password_confirmation: "outra-coisa" }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", /Confirmação da (password|palavra-passe)/i
  end

  test "update with a password shorter than 8 characters" do
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "curta", password_confirmation: "curta" }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "update with a blank password does not pretend to reset" do
    @user.sessions.create!
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "", password_confirmation: "" }
    end

    assert_response :unprocessable_entity
    assert_equal 1, @user.sessions.count
  end

  private
    def assert_notice(text)
      assert_select ".flash", /#{text}/
    end
end
