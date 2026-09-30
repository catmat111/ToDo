require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "is valid with a name and a palette colour" do
    tag = users(:one).tags.new(name: "Universidade", color: Tag::COLORS.first)
    assert tag.valid?
  end

  test "requires a name with a pt-PT message" do
    tag = users(:one).tags.new(name: "  ")
    assert_not tag.valid?
    assert_includes tag.errors.full_messages, "Nome não pode ficar em branco"
  end

  test "limits the name to 40 characters" do
    tag = users(:one).tags.new(name: "a" * 41)
    assert_not tag.valid?
    assert tag.errors.of_kind?(:name, :too_long)
  end

  test "squishes whitespace in the name" do
    tag = users(:one).tags.create!(name: "  Casa   e   jardim ")
    assert_equal "Casa e jardim", tag.name
  end

  test "name is unique per user, ignoring case" do
    users(:one).tags.create!(name: "Trabalho")
    duplicate = users(:one).tags.new(name: "trabalho")
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:name, :taken)
    assert_includes duplicate.errors.full_messages, "Nome já existe numa das tuas etiquetas"
  end

  test "the same name is allowed for different users" do
    users(:one).tags.create!(name: "Trabalho")
    assert users(:two).tags.new(name: "Trabalho").valid?
  end

  test "colour must be a six digit hex and is normalised to upper case" do
    tag = users(:one).tags.new(name: "Cor", color: "red")
    assert_not tag.valid?
    assert tag.errors.of_kind?(:color, :invalid)

    tag.color = " #b5835a "
    assert tag.valid?
    assert_equal "#B5835A", tag.color
  end

  test "colour is optional" do
    tag = users(:one).tags.create!(name: "Sem cor", color: "")
    assert_nil tag.color
    assert tag.palette_color?
  end

  test "with_task_counts counts only non-archived tasks" do
    tag = users(:one).tags.create!(name: "Contagem")
    empty = users(:one).tags.create!(name: "Vazia")
    create_task(tags: [ tag ])
    create_task(tags: [ tag ])
    create_task(tags: [ tag ], archived_at: Time.current)

    counts = users(:one).tags.with_task_counts.index_by(&:id)
    assert_equal 2, counts[tag.id].tasks_count
    assert_equal 0, counts[empty.id].tasks_count
    assert_equal 2, tag.reload.tasks_count
  end

  test "destroying a tag keeps its tasks" do
    tag = users(:one).tags.create!(name: "Temporária")
    task = create_task(tags: [ tag ])
    assert_difference -> { TaskTag.count }, -1 do
      tag.destroy!
    end
    assert Task.exists?(task.id)
  end

  test "colour names are human friendly" do
    assert_equal "Terracota", Tag.color_name("#9c5d3c")
    assert_equal "#123456", Tag.color_name("#123456")
  end
end
