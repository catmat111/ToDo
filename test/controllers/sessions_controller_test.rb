require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "new renders the pt-PT login form" do
    get new_session_path

    assert_response :success
    assert_select "h2", "Entrar"
    assert_select "form.form[action=?]", session_path do
      assert_select "input[type=email][name=email_address]"
      assert_select "input[type=password][name=password]"
      assert_select "input[type=submit].btn--primary.btn--block[value=?]", "Entrar"
    end
    assert_select "a[href=?]", new_password_path, text: "Esqueceste-te da password?"
    assert_select "a[href=?]", new_registration_path, text: "Criar conta"
  end

  test "new redirects home when already signed in" do
    sign_in_as @user

    get new_session_path

    assert_redirected_to root_path
  end

  test "create with valid credentials signs in and audits" do
    assert_difference -> { @user.sessions.count }, 1 do
      post session_path, params: { email_address: @user.email_address, password: "password" }
    end

    assert_redirected_to root_path
    assert cookies[:session_id]
    assert_equal "Olá de novo, Ana!", flash[:notice]
    log = AuditLog.order(:id).last
    assert_equal "user.signed_in", log.action
    assert_equal @user, log.user
  end

  test "create is case-insensitive on the email address" do
    post session_path, params: { email_address: "  ONE@example.com ", password: "password" }

    assert_redirected_to root_path
  end

  test "create redirects back to the page that required authentication" do
    get profile_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to profile_url
  end

  test "create with a wrong password shows a generic message" do
    post session_path, params: { email_address: @user.email_address, password: "wrong-password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
    follow_redirect!
    assert_select ".flash--alert", /Email ou password incorretos/
  end

  test "create with an unknown email shows exactly the same message" do
    post session_path, params: { email_address: @user.email_address, password: "wrong-password" }
    known_message = flash[:alert]

    post session_path, params: { email_address: "nobody@example.com", password: "wrong-password" }

    assert_redirected_to new_session_path
    assert_equal known_message, flash[:alert]
    assert_no_match(/exist|encontr/i, flash[:alert])
  end

  test "destroy signs out and redirects to login with a notice" do
    sign_in_as @user

    assert_difference -> { @user.sessions.count }, -1 do
      delete session_path
    end

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
    follow_redirect!
    assert_select ".flash--notice", /Sessão terminada/
  end

  test "protected pages redirect to login when signed out" do
    [ profile_path, edit_profile_path, password_profile_path, audit_logs_path ].each do |path|
      get path
      assert_redirected_to new_session_path, "#{path} should require authentication"
    end

    delete profile_path, params: { password: "password" }
    assert_redirected_to new_session_path
    assert User.exists?(@user.id)
  end
end
