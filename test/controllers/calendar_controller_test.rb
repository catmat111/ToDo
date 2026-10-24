require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-14 10:00")
    sign_in_as users(:one)
  end

  test "draws a deadline line on every day from start to deadline" do
    create_task(users(:one), title: "Relatório", starts_at: Time.zone.parse("2026-10-12 09:00"), due_at: Time.zone.parse("2026-10-16 18:00"))

    get calendar_path(month: "2026-10")
    assert_response :success
    assert_select "a.calendar-span", 5
    assert_select "a.calendar-span--start", 1
    assert_select "a.calendar-span--end", 1
    assert_select "a.calendar-span .calendar-span__title", 1
    assert_select "a.calendar-span--end .calendar-span__due", /18:00/

    get calendar_path(view: "week", date: "2026-10-14")
    assert_select ".calendar-week__item--span", 5
  end
end
