require "test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @task = create_task(@user)
    sign_in_as(@user)
  end

  def link_params(linkable, **overrides)
    { link: { linkable_type: linkable.class.name, linkable_id: linkable.id,
              url: "https://example.com/doc", label: "Documento" }.merge(overrides) }
  end

  test "requires authentication" do
    sign_out
    post links_path, params: link_params(@task)
    assert_redirected_to new_session_path
  end

  test "create adds a link to the user's task and redirects back to it" do
    assert_difference -> { @task.links.count }, 1 do
      post links_path, params: link_params(@task)
    end
    link = @task.links.last
    assert_equal @user, link.user
    assert_equal "Documento", link.label
    assert_redirected_to task_path(@task)
    assert_equal "Link adicionado.", flash[:notice]
    assert AuditLog.exists?(action: "link.created", resource_type: "Link", resource_id: link.id)
  end

  test "create redirects back to the referring page when there is one" do
    post links_path, params: link_params(@task), headers: { "HTTP_REFERER" => "http://www.example.com/tasks/#{@task.id}?tab=links" }
    assert_redirected_to "http://www.example.com/tasks/#{@task.id}?tab=links"
  end

  test "create adds a link to the user's job application" do
    application = create_job_application(@user)
    assert_difference -> { application.links.count }, 1 do
      post links_path, params: link_params(application, label: "")
    end
    assert_nil application.links.last.label
    assert_redirected_to job_application_path(application)
  end

  test "create with an invalid url does not save and explains why" do
    assert_no_difference -> { Link.count } do
      post links_path, params: link_params(@task, url: "javascript:alert(1)")
    end
    assert_redirected_to task_path(@task)
    assert_match "URL tem de começar por http:// ou https://", flash[:alert]
  end

  test "create cannot attach a link to another user's task" do
    foreign_task = create_task(users(:two))
    assert_no_difference -> { Link.count } do
      post links_path, params: link_params(foreign_task)
    end
    assert_response :not_found
  end

  test "create cannot attach a link to another user's job application" do
    foreign_application = create_job_application(users(:two))
    assert_no_difference -> { Link.count } do
      post links_path, params: link_params(foreign_application)
    end
    assert_response :not_found
  end

  test "create rejects unsupported linkable types" do
    tag = @user.tags.create!(name: "Etiqueta")
    [ "Tag", "User", "Kernel", "" ].each do |type|
      assert_no_difference -> { Link.count } do
        post links_path, params: link_params(tag, linkable_type: type)
      end
      assert_response :not_found
    end
  end

  test "create ignores a forged user_id" do
    post links_path, params: link_params(@task, user_id: users(:two).id)
    assert_equal @user, Link.last.user
  end

  test "destroy removes the user's link and returns to the linkable" do
    link = @user.links.create!(linkable: @task, url: "https://example.com")
    assert_difference -> { Link.count }, -1 do
      delete link_path(link)
    end
    assert_redirected_to task_path(@task)
    assert_response :see_other
    assert_equal "Link removido.", flash[:notice]
    assert AuditLog.exists?(action: "link.destroyed", resource_id: link.id)
  end

  test "another user cannot destroy the link" do
    link = @user.links.create!(linkable: @task, url: "https://example.com")
    sign_out
    sign_in_as(users(:two))

    assert_no_difference -> { Link.count } do
      delete link_path(link)
    end
    assert_response :not_found
  end
end

class LinksSectionPartialTest < ActionView::TestCase
  test "renders links, delete buttons and the add form" do
    task = create_task(users(:one))
    link = users(:one).links.create!(linkable: task, url: "https://www.example.com/enunciado", label: "Enunciado")

    render partial: "links/section", locals: { linkable: task }

    assert_select "section.card.links-section"
    assert_select "a[href='https://www.example.com/enunciado'][target=_blank][rel='noopener noreferrer']", "Enunciado"
    assert_select ".list__meta", /example\.com/
    assert_select "form[action=?]", link_path(link) do
      assert_select "input[name=_method][value=delete]"
    end
    assert_select "form[action=?]", links_path do
      assert_select "input[type=hidden][name='link[linkable_type]'][value=Task]"
      assert_select "input[type=hidden][name='link[linkable_id]'][value=?]", task.id.to_s
      assert_select "input[type=url][name='link[url]'][required]"
      assert_select "input[name='link[label]']"
      assert_select "label", "Endereço (URL)"
    end
  end

  test "renders an empty message without links" do
    application = create_job_application(users(:one))
    render partial: "links/section", locals: { linkable: application }
    assert_select ".links-section__empty"
    assert_select "input[type=hidden][name='link[linkable_type]'][value=JobApplication]"
  end
end
