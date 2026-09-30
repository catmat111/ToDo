require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @tag = @user.tags.create!(name: "Universidade", color: "#9C5D3C")
    sign_in_as(@user)
  end

  test "requires authentication" do
    sign_out
    get tags_path
    assert_redirected_to new_session_path
  end

  test "index lists the user's tags with task counts and filter links" do
    create_task(@user, tags: [ @tag ])
    users(:two).tags.create!(name: "Segredo do Bruno")

    get tags_path
    assert_response :success
    assert_select "h1", "Etiquetas"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@tag)}" do
      assert_select ".chip", "Universidade"
      assert_select ".tag-card__number", "1"
      assert_select "a[href=?]", tasks_path(tag_id: @tag.id)
      assert_select "a[href=?]", edit_tag_path(@tag)
      assert_select "form[action=?]", tag_path(@tag)
    end
    assert_no_match "Segredo do Bruno", response.body
  end

  test "index shows an empty state without tags" do
    @tag.destroy!
    get tags_path
    assert_response :success
    assert_select ".empty-state"
  end

  test "new renders the form with palette swatches and a custom colour" do
    get new_tag_path
    assert_response :success
    assert_select "form[action=?]", tags_path do
      assert_select "input[name='tag[name]'][required]"
      Tag::COLORS.each do |hex|
        assert_select "input[type=radio][name='tag[color]'][value=?]", hex
      end
      assert_select "input[type=radio][name='tag[color]'][value='#9C5D3C'][checked]"
      assert_select "input[type=color]#tag_color_picker"
      assert_select "label[for=tag_color_picker]"
    end
  end

  test "create saves a tag for the current user" do
    assert_difference -> { @user.tags.count }, 1 do
      post tags_path, params: { tag: { name: "Casa", color: "#6e6b41" } }
    end
    tag = @user.tags.find_by!(name: "Casa")
    assert_equal "#6E6B41", tag.color
    assert_redirected_to tags_path
    assert_equal "Etiqueta “Casa” criada.", flash[:notice]
    assert AuditLog.exists?(action: "tag.created", resource_type: "Tag", resource_id: tag.id, user_id: @user.id)
  end

  test "create accepts a custom colour" do
    post tags_path, params: { tag: { name: "Azul", color: "#1F6FEB" } }
    assert_equal "#1F6FEB", @user.tags.find_by!(name: "Azul").color
  end

  test "create ignores a user_id param" do
    post tags_path, params: { tag: { name: "Minha", user_id: users(:two).id } }
    assert_equal @user, Tag.find_by!(name: "Minha").user
  end

  test "create shows the uniqueness error case-insensitively" do
    assert_no_difference -> { Tag.count } do
      post tags_path, params: { tag: { name: "universidade", color: "#9C5D3C" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors", /Nome já existe numa das tuas etiquetas/
    assert_select ".field__error", /já existe/
  end

  test "create allows a name another user already has" do
    users(:two).tags.create!(name: "Casa")
    assert_difference -> { @user.tags.count }, 1 do
      post tags_path, params: { tag: { name: "Casa" } }
    end
    assert_redirected_to tags_path
  end

  test "create re-renders on invalid colour" do
    post tags_path, params: { tag: { name: "Cor má", color: "vermelho" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors", /Cor/
  end

  test "edit renders the form" do
    get edit_tag_path(@tag)
    assert_response :success
    assert_select "input[name='tag[name]'][value=?]", "Universidade"
    assert_select "input[type=radio][value='#9C5D3C'][checked]"
  end

  test "edit checks the custom radio for a non-palette colour" do
    @tag.update!(color: "#123ABC")
    get edit_tag_path(@tag)
    assert_select "input#tag_color_custom[value='#123ABC'][checked]"
  end

  test "update changes the tag" do
    patch tag_path(@tag), params: { tag: { name: "Faculdade", color: "#B07E1E" } }
    assert_redirected_to tags_path
    @tag.reload
    assert_equal [ "Faculdade", "#B07E1E" ], [ @tag.name, @tag.color ]
    log = AuditLog.find_by!(action: "tag.updated", resource_id: @tag.id)
    assert_equal "Universidade", log.metadata["previous_name"]
  end

  test "update re-renders with errors" do
    @user.tags.create!(name: "Casa")
    patch tag_path(@tag), params: { tag: { name: "CASA" } }
    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_equal "Universidade", @tag.reload.name
  end

  test "destroy removes the tag but keeps tasks" do
    task = create_task(@user, tags: [ @tag ])
    assert_difference -> { Tag.count }, -1 do
      delete tag_path(@tag)
    end
    assert_redirected_to tags_path
    assert_response :see_other
    assert Task.exists?(task.id)
    assert AuditLog.exists?(action: "tag.destroyed", resource_id: @tag.id)
  end

  test "another user cannot see, edit, update or destroy the tag" do
    sign_out
    sign_in_as(users(:two))

    get edit_tag_path(@tag)
    assert_response :not_found

    patch tag_path(@tag), params: { tag: { name: "Roubada" } }
    assert_response :not_found

    assert_no_difference -> { Tag.count } do
      delete tag_path(@tag)
    end
    assert_response :not_found
    assert_equal "Universidade", @tag.reload.name
  end
end
