require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @current_session = @user.sessions.order(:id).last
  end

  # --- show ---------------------------------------------------------------

  test "show renders the signed-in user's profile" do
    get profile_path

    assert_response :success
    assert_select "h1", "Perfil"
    assert_select ".profile-hero__name", "Ana Silva"
    assert_select ".profile-hero__email", "one@example.com"
    assert_select "#integrations-title", "Integrações"
    assert_select "a[href=?]", calendar_connection_path
    assert_select ".badge", "Não ligado"
    assert_select "a[href=?]", edit_profile_path
    assert_select "a[href=?]", password_profile_path
    assert_select "a[href=?]", audit_logs_path
    assert_select "form[action=?] input[type=password][name=password]", profile_path
    assert_no_match "Bruno Costa", response.body
  end

  test "show reports the Google Calendar connection status" do
    @user.calendar_connections.create!(provider: "google", access_token: "secret-token", last_synced_at: 2.hours.ago)

    get profile_path

    assert_select ".badge--active", "Ligado"
    assert_match "Última sincronização há", response.body
    assert_no_match "secret-token", response.body
  end

  test "show counts sessions on other devices" do
    @user.sessions.create!
    @user.sessions.create!

    get profile_path

    assert_match "e mais 2 sessões noutros dispositivos", response.body
  end

  test "show renders the objective when present" do
    @user.update!(objective: "Encontrar um estágio")

    get profile_path

    assert_select ".profile-objective", /Encontrar um estágio/
  end

  test "each user only ever sees their own profile" do
    sign_in_as users(:two)

    get profile_path

    assert_select ".profile-hero__name", "Bruno Costa"
    assert_no_match "one@example.com", response.body
  end

  # --- edit / update -------------------------------------------------------

  test "edit renders the form with theme and timezone selects" do
    get edit_profile_path

    assert_response :success
    assert_select "form[action=?]", profile_path do
      assert_select "input[name='user[name]'][value=?]", "Ana Silva"
      assert_select "input[type=email][name='user[email_address]']"
      assert_select "input[type=url][name='user[avatar_url]']"
      assert_select "textarea[name='user[objective]']"
      assert_select "select[name='user[theme]'] option[value=light]", "Claro"
      assert_select "select[name='user[theme]'] option[value=dark]", "Escuro"
      assert_select "select[name='user[timezone]'] option[selected][value='Europe/Lisbon']", /Lisboa/
      assert_select "select[name='user[timezone]'] option[value='America/Sao_Paulo']"
    end
  end

  test "update saves the profile, audits the changed fields and applies the theme" do
    patch profile_path, params: { user: { name: "Ana Maria Silva", theme: "dark", timezone: "Atlantic/Azores",
                                          objective: "Acabar a tese", avatar_url: "https://example.com/ana.png" } }

    assert_redirected_to profile_path
    @user.reload
    assert_equal "Ana Maria Silva", @user.name
    assert_equal "dark", @user.theme
    assert_equal "Atlantic/Azores", @user.timezone
    assert_equal "Acabar a tese", @user.objective

    log = AuditLog.order(:id).last
    assert_equal "user.updated", log.action
    assert_equal @user, log.user
    assert_equal %w[avatar_url name objective theme timezone], log.metadata["fields"].sort

    follow_redirect!
    assert_select "html[data-theme=dark]"
    assert_select ".flash--notice", /Perfil atualizado/
  end

  test "update rejects an unknown theme" do
    patch profile_path, params: { user: { theme: "neon" } }

    assert_response :unprocessable_entity
    assert_equal "light", @user.reload.theme
    assert_select ".form-errors", /Tema/
    # The layout keeps the persisted theme, not the rejected value.
    assert_select "html[data-theme=light]"
  end

  test "update rejects an unknown timezone" do
    patch profile_path, params: { user: { timezone: "Europe/Atlantis" } }

    assert_response :unprocessable_entity
    assert_equal "Europe/Lisbon", @user.reload.timezone
    assert_select ".form-errors", /Fuso horário/
  end

  test "update rejects invalid email and avatar values without crashing" do
    patch profile_path, params: { current_password: "password", user: { email_address: "sem-arroba", avatar_url: "javascript:alert(1)" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email_address
    assert_nil @user.avatar_url
    assert_select "img[src*=javascript]", count: 0
  end

  test "update rejects an email already used by another account" do
    patch profile_path, params: { current_password: "password", user: { email_address: "two@example.com" } }

    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email_address
  end

  test "update ignores the password and other unpermitted attributes" do
    assert_no_changes -> { @user.reload.password_digest } do
      patch profile_path, params: { user: { name: "Ana", password: "hackeado123", password_confirmation: "hackeado123" } }
    end
    assert_redirected_to profile_path
  end

  test "update with nothing changed does not write an audit entry" do
    assert_no_difference -> { AuditLog.count } do
      patch profile_path, params: { user: { name: @user.name } }
    end
    assert_redirected_to profile_path
  end

  # --- password -------------------------------------------------------------

  test "edit_password renders the form" do
    get password_profile_path

    assert_response :success
    assert_select "form[action=?]", password_profile_path do
      assert_select "input[type=password][name='user[current_password]']"
      assert_select "input[type=password][name='user[password]']"
      assert_select "input[type=password][name='user[password_confirmation]']"
    end
  end

  test "update_password requires the current password" do
    other_session = @user.sessions.create!

    assert_no_changes -> { @user.reload.password_digest } do
      patch password_profile_path, params: { user: { current_password: "errada", password: "nova-password",
                                                     password_confirmation: "nova-password" } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", /Password atual está incorreta/
    assert Session.exists?(other_session.id)
  end

  test "update_password changes the password and ends only the other sessions" do
    other_session = @user.sessions.create!
    someone_elses_session = users(:two).sessions.create!

    patch password_profile_path, params: { user: { current_password: "password", password: "nova-password",
                                                   password_confirmation: "nova-password" } }

    assert_redirected_to profile_path
    assert @user.reload.authenticate("nova-password")
    assert_not Session.exists?(other_session.id)
    assert Session.exists?(@current_session.id), "the current session must survive"
    assert Session.exists?(someone_elses_session.id)
    assert_equal "user.password_changed", AuditLog.order(:id).last.action

    get profile_path
    assert_response :success
  end

  test "update_password rejects a mismatched confirmation" do
    assert_no_changes -> { @user.reload.password_digest } do
      patch password_profile_path, params: { user: { current_password: "password", password: "nova-password",
                                                     password_confirmation: "outra-password" } }
    end

    assert_response :unprocessable_entity
  end

  test "update_password rejects a short or blank new password" do
    [ "curta", "" ].each do |new_password|
      assert_no_changes -> { @user.reload.password_digest } do
        patch password_profile_path, params: { user: { current_password: "password", password: new_password,
                                                       password_confirmation: new_password } }
      end
      assert_response :unprocessable_entity
    end
  end

  # --- destroy --------------------------------------------------------------

  test "destroy requires the password" do
    assert_no_difference -> { User.count } do
      delete profile_path, params: { password: "errada" }
    end

    assert_redirected_to profile_path(anchor: "zona-de-perigo")
    assert_equal "Password incorreta. A tua conta não foi eliminada.", flash[:alert]
    assert Session.exists?(@current_session.id)
  end

  test "destroy without a password does nothing" do
    assert_no_difference -> { User.count } do
      delete profile_path
    end

    assert_redirected_to profile_path(anchor: "zona-de-perigo")
  end

  test "destroy deletes the account and its data, signs out and audits" do
    parent = create_task(@user)
    create_task(@user, parent_task: parent)
    tag = @user.tags.create!(name: "Pessoal")
    parent.tags << tag
    create_job_application(@user)
    AuditLog.record("task.created", resource: parent, user: @user)
    other_task = create_task(users(:two))

    delete profile_path, params: { password: "password" }

    assert_redirected_to new_session_path
    assert_not User.exists?(@user.id)
    assert_equal 0, Task.where(user_id: @user.id).count
    assert_equal 0, Session.where(user_id: @user.id).count
    assert Task.exists?(other_task.id)
    assert User.exists?(users(:two).id)
    assert_empty cookies[:session_id]

    log = AuditLog.find_by!(action: "user.deleted")
    assert_nil log.user_id
    assert_equal @user.id, log.resource_id
    assert_equal "one@example.com", log.metadata["email"]
    assert_nil AuditLog.find_by!(action: "task.created").user_id

    follow_redirect!
    assert_select ".flash--notice", /conta e todos os teus dados foram eliminados/
    get profile_path
    assert_redirected_to new_session_path
  end

  test "destroy by another user only deletes that user's own account" do
    sign_in_as users(:two)

    delete profile_path, params: { password: "password" }

    assert User.exists?(@user.id)
    assert_not User.exists?(users(:two).id)
  end

  test "theme toggle cycles the theme and goes back" do
    patch theme_profile_path, params: { theme: "system" }, headers: { "HTTP_REFERER" => tasks_url }
    assert_redirected_to tasks_url
    assert_equal "system", @user.reload.theme

    get profile_path
    assert_select "html[data-theme=system]"
    assert_select "meta[name=color-scheme][content='light dark']"
  end

  test "theme toggle rejects unknown themes" do
    patch theme_profile_path, params: { theme: "neon" }
    assert_equal "light", @user.reload.theme
    assert_equal "Tema inválido.", flash[:alert]
  end

  test "signed-out pages follow the system theme" do
    sign_out
    get new_session_path
    assert_select "html[data-theme=system]"
  end

  test "changing the email requires the current password" do
    patch profile_path, params: { user: { email_address: "novo@example.com" } }
    assert_response :unprocessable_entity
    assert_equal "one@example.com", @user.reload.email_address

    patch profile_path, params: { current_password: "errada", user: { email_address: "novo@example.com" } }
    assert_equal "one@example.com", @user.reload.email_address

    patch profile_path, params: { current_password: "password", user: { email_address: "novo@example.com" } }
    assert_redirected_to profile_path
    assert_equal "novo@example.com", @user.reload.email_address
  end

  test "other fields don't need the password" do
    patch profile_path, params: { user: { name: "Ana Maria", email_address: "one@example.com" } }
    assert_redirected_to profile_path
    assert_equal "Ana Maria", @user.reload.name
  end
end
