require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attrs)
    User.new({ name: "Carla", email_address: "carla@example.com", password: "segredo123" }.merge(attrs))
  end

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "strips the name" do
    assert_equal "Carla", build_user(name: "  Carla  ").name
  end

  test "defaults to the light theme and Lisbon" do
    user = build_user
    assert user.valid?
    assert_equal "light", user.theme
    assert_equal "Europe/Lisbon", user.timezone
  end

  test "requires name and a valid, unique email" do
    assert_not build_user(name: "").valid?
    assert_not build_user(email_address: "not-an-email").valid?
    assert_not build_user(email_address: "ONE@example.com").valid?
  end

  test "password must have between 8 and 72 characters" do
    assert_not build_user(password: "1234567").valid?
    assert build_user(password: "12345678").valid?
    assert_not build_user(password: "a" * 73).valid?
  end

  test "theme must be light or dark" do
    assert build_user(theme: "dark").valid?
    assert_not build_user(theme: "neon").valid?
  end

  test "timezone must be a known IANA identifier" do
    assert build_user(timezone: "Atlantic/Azores").valid?
    assert build_user(timezone: "America/Sao_Paulo").valid?
    assert_not build_user(timezone: "Lisbon").valid?
    assert_not build_user(timezone: "Mars/Olympus_Mons").valid?
  end

  test "avatar_url must be an http(s) URL" do
    assert build_user(avatar_url: "https://example.com/a.png").valid?
    assert build_user(avatar_url: "").valid?
    assert_not build_user(avatar_url: "javascript:alert(1)").valid?
    assert_not build_user(avatar_url: "https://example.com/a.png\n<script>").valid?
    assert_not build_user(avatar_url: "https://").valid?
  end

  test "objective is limited to 2000 characters" do
    assert build_user(objective: "a" * 2000).valid?
    assert_not build_user(objective: "a" * 2001).valid?
  end

  test "time_zone falls back to Lisbon" do
    assert_equal "Atlantic/Azores", build_user(timezone: "Atlantic/Azores").time_zone.tzinfo.name
    assert_equal "Europe/Lisbon", build_user(timezone: "invalid").time_zone.tzinfo.name
  end

  test "first_name" do
    assert_equal "Ana", users(:one).first_name
  end

  test "authenticate_by works with the fixture password" do
    assert_equal users(:one), User.authenticate_by(email_address: "one@example.com", password: "password")
    assert_nil User.authenticate_by(email_address: "one@example.com", password: "wrong")
  end

  test "every timezone option offered by the UI is valid" do
    AccountHelper.timezone_options.each do |_label, identifier|
      assert build_user(timezone: identifier).valid?, "#{identifier} should be accepted"
    end
    assert_equal AccountHelper.timezone_options.map(&:last).uniq.size, AccountHelper.timezone_options.size
  end

  test "destroying a user removes their data and keeps the audit trail anonymised" do
    user = users(:one)
    parent = create_task(user)
    create_task(user, parent_task: parent)
    log = AuditLog.record("task.created", resource: parent, user: user)

    user.destroy!

    assert_equal 0, Task.where(user_id: user.id).count
    assert_nil log.reload.user_id
  end
end
