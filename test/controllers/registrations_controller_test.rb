require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def valid_params(**overrides)
    { user: { name: "Carla Mendes", email_address: "carla@example.com", password: "segredo123",
              password_confirmation: "segredo123", timezone: "Europe/Lisbon" }.merge(overrides) }
  end

  test "new renders the form with Lisbon preselected" do
    get new_registration_path

    assert_response :success
    assert_select "h2", "Criar conta"
    assert_select "form[action=?]", registration_path do
      assert_select "input[name='user[name]']"
      assert_select "input[type=email][name='user[email_address]']"
      assert_select "input[type=password][name='user[password]']"
      assert_select "input[type=password][name='user[password_confirmation]']"
      assert_select "select[name='user[timezone]'] option[selected][value='Europe/Lisbon']"
    end
    assert_select "a[href=?]", new_session_path
  end

  test "new redirects home when already signed in" do
    sign_in_as users(:one)

    get new_registration_path

    assert_redirected_to root_path
  end

  test "create redirects home when already signed in" do
    sign_in_as users(:one)

    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params
    end
    assert_redirected_to root_path
  end

  test "create registers the user, signs them in and audits" do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: valid_params(email_address: "  Carla@Example.com ", timezone: "Atlantic/Azores")
    end

    user = User.order(:id).last
    assert_redirected_to root_path
    assert_match "Bem-vindo(a) ao ToDo, Carla!", flash[:notice]
    assert cookies[:session_id]
    assert_equal 1, user.sessions.count
    assert_equal "carla@example.com", user.email_address
    assert_equal "Atlantic/Azores", user.timezone
    assert_equal "light", user.theme
    assert user.authenticate("segredo123")

    log = AuditLog.order(:id).last
    assert_equal "user.registered", log.action
    assert_equal user, log.user
    assert_equal [ "User", user.id ], [ log.resource_type, log.resource_id ]
  end

  test "create ignores attributes that are not part of the form" do
    post registration_path, params: valid_params(theme: "dark", avatar_url: "https://example.com/a.png")

    user = User.order(:id).last
    assert_equal "light", user.theme
    assert_nil user.avatar_url
  end

  test "create with invalid data re-renders the form" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(name: "", email_address: "nope")
    end

    assert_response :unprocessable_entity
    assert_nil cookies[:session_id]
    assert_select ".form-errors li", minimum: 2
    assert_select "input[name='user[email_address]'][value='nope']"
  end

  test "create rejects a duplicate email regardless of case" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(email_address: "ONE@example.com")
    end

    assert_response :unprocessable_entity
  end

  test "create rejects a short password" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(password: "curta", password_confirmation: "curta")
    end

    assert_response :unprocessable_entity
  end

  test "create rejects a mismatched confirmation" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(password_confirmation: "diferente123")
    end

    assert_response :unprocessable_entity
  end

  test "create rejects an unknown timezone" do
    assert_no_difference -> { User.count } do
      post registration_path, params: valid_params(timezone: "Mars/Olympus_Mons")
    end

    assert_response :unprocessable_entity
  end

  test "create without the user key is a bad request" do
    post registration_path, params: { name: "x" }

    assert_response :bad_request
  end
end
