require "test_helper"

class SecurityTest < ActionDispatch::IntegrationTest
  setup { @user = users(:one) }

  test "direct uploads require a signed-in user" do
    post rails_direct_uploads_path, params: { blob: { filename: "x.png", byte_size: 10, checksum: "abc", content_type: "image/png" } }
    assert_response :unauthorized
    assert_equal 0, ActiveStorage::Blob.count
  end

  test "sessions expire after 30 days without use" do
    sign_in_as @user
    Current.session.update_column(:updated_at, 31.days.ago)

    get root_path
    assert_redirected_to new_session_path
    assert_not Session.exists?(Current.session.id)
  end

  test "recent sessions keep working" do
    sign_in_as @user
    Current.session.update_column(:updated_at, 2.days.ago)
    get root_path
    assert_response :success
  end

  test "security headers are sent" do
    sign_in_as @user
    get root_path
    policy = response.headers["Permissions-Policy"] || response.headers["Feature-Policy"]
    assert_match "camera", policy.to_s
    assert response.headers["Content-Security-Policy"].present?
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "another user's records are never reachable" do
    task = create_task(users(:two))
    application = create_job_application(users(:two))
    sign_in_as @user

    get task_path(task)
    assert_response :not_found
    get job_application_path(application)
    assert_response :not_found
    patch complete_task_path(task)
    assert_response :not_found
  end
end
