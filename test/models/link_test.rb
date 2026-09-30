require "test_helper"

class LinkTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = create_task(@user)
  end

  test "is valid for the owner's task with an http(s) url" do
    link = @user.links.new(linkable: @task, url: "https://example.com/enunciado.pdf", label: "Enunciado")
    assert link.valid?
  end

  test "can be attached to a job application" do
    application = create_job_application(@user)
    link = @user.links.create!(linkable: application, url: "https://empresa.pt/vaga")
    assert_includes application.links, link
  end

  test "url is required and must start with http:// or https://" do
    link = @user.links.new(linkable: @task, url: "")
    assert_not link.valid?
    assert_includes link.errors.full_messages, "URL não pode ficar em branco"

    %w[ftp://example.com javascript:alert(1) example.com https://exa\ mple.com].each do |bad|
      link.url = bad
      assert_not link.valid?, "#{bad.inspect} should be rejected"
      assert link.errors.of_kind?(:url, :invalid)
    end

    link.url = "  http://example.com/a?b=c  "
    assert link.valid?
    assert_equal "http://example.com/a?b=c", link.url
  end

  test "url and label have length limits" do
    link = @user.links.new(linkable: @task, url: "https://example.com/#{'a' * 2000}", label: "x" * 101)
    assert_not link.valid?
    assert link.errors.of_kind?(:url, :too_long)
    assert link.errors.of_kind?(:label, :too_long)
  end

  test "rejects a linkable that belongs to another user" do
    foreign_task = create_task(users(:two))
    link = @user.links.new(linkable: foreign_task, url: "https://example.com")
    assert_not link.valid?
    assert_includes link.errors.full_messages, "Recurso associado tem de pertencer ao mesmo utilizador"

    foreign_application = create_job_application(users(:two))
    link.linkable = foreign_application
    assert_not link.valid?
    assert link.errors.added?(:linkable, "tem de pertencer ao mesmo utilizador")
  end

  test "only allows supported linkable types" do
    link = @user.links.new(linkable: @user.tags.create!(name: "Etiqueta"), url: "https://example.com")
    assert_not link.valid?
    assert link.errors.of_kind?(:linkable_type, :inclusion)
  end

  test "display_label prefers the label, then the host" do
    link = @user.links.new(linkable: @task, url: "https://www.Example.com/path", label: "  ")
    assert_nil link.label
    assert_equal "example.com", link.host
    assert_equal "example.com", link.display_label

    link.label = "Documento"
    assert_equal "Documento", link.display_label
  end

  test "display_label falls back to the url when it cannot be parsed" do
    link = Link.new(url: "http://exa mple.com")
    assert_nil link.host
    assert_equal "http://exa mple.com", link.display_label
  end

  test "is destroyed with its linkable" do
    @user.links.create!(linkable: @task, url: "https://example.com")
    assert_difference -> { Link.count }, -1 do
      @task.destroy!
    end
  end
end
