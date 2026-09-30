require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  def build_notification(**attrs)
    @user.notifications.build({ notification_type: "system", title: "Olá" }.merge(attrs))
  end

  test "requires a known type and a title" do
    assert build_notification.valid?
    assert_not build_notification(notification_type: "spam").valid?
    assert_not build_notification(title: "").valid?
  end

  test "mark_read! sets read_at once" do
    notification = build_notification.tap(&:save!)
    assert_not notification.read?
    notification.mark_read!
    first_read = notification.read_at
    assert notification.read?

    travel 1.hour do
      notification.mark_read!
      assert_equal first_read, notification.reload.read_at
    end
  end

  test "for_filter and mark_all_read! only touch the given scope" do
    mine = build_notification.tap(&:save!)
    read = build_notification(read_at: 1.day.ago).tap(&:save!)
    other = users(:two).notifications.create!(notification_type: "system", title: "Outro")

    assert_equal [ mine ], @user.notifications.for_filter("unread").to_a
    assert_equal 2, @user.notifications.for_filter("all").count

    assert_equal 1, @user.notifications.mark_all_read!
    assert mine.reload.read?
    assert read.reload.read?
    assert_not other.reload.read?
  end

  test "type_label is in Portuguese" do
    assert_equal "Lembrete", build_notification(notification_type: "reminder").type_label
    assert_equal "Prazo", build_notification(notification_type: "task_due").type_label
  end
end
