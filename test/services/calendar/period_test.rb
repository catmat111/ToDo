require "test_helper"

class Calendar::PeriodTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 9, 29) # a Tuesday

  def period(params = {})
    Calendar::Period.from_params(ActionController::Parameters.new(params), today: TODAY)
  end

  test "defaults to the current month, Monday first" do
    p = period
    assert p.month?
    assert_equal Date.new(2026, 8, 31), p.first_day
    assert_equal Date.new(2026, 10, 4), p.last_day
    assert_equal 5, p.weeks.size
    assert p.weeks.all? { |week| week.first.monday? && week.size == 7 }
    assert_equal "Setembro de 2026", p.title
    assert p.today?(TODAY)
    assert p.contains_today?
  end

  test "parses ?month and navigates" do
    p = period(month: "2026-12")
    assert_equal "Dezembro de 2026", p.title
    assert_equal({ month: "2026-11" }, p.previous_params)
    assert_equal({ month: "2027-01" }, p.next_params)
    assert_not p.in_focus?(Date.new(2026, 11, 30))
    assert_not p.contains_today?
  end

  test "invalid params fall back to today" do
    assert_equal "Setembro de 2026", period(month: "2026-13").title
    assert_equal "Setembro de 2026", period(month: "abc").title
    assert_equal TODAY.beginning_of_week, period(view: "week", date: "2026-02-31").first_day
    assert period(view: "bogus").month?
  end

  test "week view" do
    p = period(view: "week", date: "2026-10-01")
    assert p.week?
    assert_equal Date.new(2026, 9, 28), p.first_day
    assert_equal Date.new(2026, 10, 4), p.last_day
    assert_equal 7, p.days.size
    assert_equal "28 de setembro – 4 de outubro de 2026", p.title
    assert_equal({ view: "week", date: "2026-09-24" }, p.previous_params)
    assert_equal({ view: "week", date: "2026-10-08" }, p.next_params)
  end

  test "time range covers whole visible days in the current zone" do
    range = period.time_range
    assert_equal Date.new(2026, 8, 31), range.begin.to_date
    assert_equal Date.new(2026, 10, 4), range.end.to_date
    assert_equal 0, range.begin.hour
  end
end
