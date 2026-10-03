require "test_helper"

class ProfileAvatarTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  def image_upload(content_type: "image/png", name: "foto.png", data: "\x89PNG\r\n\x1a\n" + ("0" * 100))
    Rack::Test::UploadedFile.new(StringIO.new(data.dup), content_type, original_filename: name)
  end

  test "uploads a profile photo and shows it in the header" do
    patch profile_path, params: { user: { avatar: image_upload } }
    assert_redirected_to profile_path
    assert @user.reload.avatar.attached?

    get root_path
    assert_select ".masthead__avatar img"
  end

  test "rejects files that are not images" do
    patch profile_path, params: { user: { avatar: image_upload(content_type: "application/pdf", name: "cv.pdf", data: "%PDF-1.4\n1 0 obj\n<<>>\nendobj\n") } }
    assert_response :unprocessable_entity
    assert_not @user.reload.avatar.attached?
  end

  test "removes the photo" do
    @user.avatar.attach(io: StringIO.new("img"), filename: "a.png", content_type: "image/png")
    patch profile_path, params: { user: { name: @user.name }, remove_avatar: "1" }
    assert_not @user.reload.avatar.attached?
  end
end
