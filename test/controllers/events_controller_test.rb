require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "creates an event and shows it on the calendar, apart from tasks" do
    assert_difference -> { users(:one).events.count }, 1 do
      post events_path, params: { event: { title: "Jantar", starts_at: "2030-06-01T20:00", ends_at: "2030-06-01T22:00", location: "Porto" } }
    end
    assert_redirected_to calendar_path(date: "2030-06-01")

    get calendar_path(date: "2030-06-01")
    assert_select "a.calendar-item--event", /Jantar/
    get calendar_path(view: "week", date: "2030-06-01")
    assert_select ".calendar-week__item--event", /20:00–22:00/
  end

  test "an all-day event covers the whole day" do
    post events_path, params: { event: { title: "Feriado", starts_at: "2030-06-10T15:00", all_day: "1" } }
    event = users(:one).events.last
    assert_equal [ Time.zone.parse("2030-06-10 00:00"), Time.zone.parse("2030-06-10").end_of_day.change(usec: 0) ], [ event.starts_at, event.ends_at ]
  end

  test "rejects an end before the start" do
    post events_path, params: { event: { title: "X", starts_at: "2030-06-01T20:00", ends_at: "2030-06-01T19:00" } }
    assert_response :unprocessable_entity
  end

  test "edits and deletes only the user's own events" do
    event = users(:one).events.create!(title: "Aula", starts_at: 1.day.from_now)
    patch event_path(event), params: { event: { title: "Aula de inglês" } }
    assert_equal "Aula de inglês", event.reload.title

    other = users(:two).events.create!(title: "Dele", starts_at: 1.day.from_now)
    get edit_event_path(other)
    assert_response :not_found

    delete event_path(event)
    assert_not Event.exists?(event.id)
  end
end
