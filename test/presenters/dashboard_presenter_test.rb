require "test_helper"

class DashboardPresenterTest < ActiveSupport::TestCase
  def sky_at(time) = DashboardPresenter.new(users(:one), now: Time.find_zone("Europe/Lisbon").parse(time)).sky

  test "the header's sky follows the clock" do
    assert_equal :dawn, sky_at("2026-10-24 06:30")[:phase]
    assert_equal :day, sky_at("2026-10-24 13:00")[:phase]
    assert_equal :dusk, sky_at("2026-10-24 19:00")[:phase]
    assert_equal :night, sky_at("2026-10-24 23:00")[:phase]
    assert_equal :night, sky_at("2026-10-24 03:00")[:phase]
  end

  test "the sun rises on the left and sets on the right; so does the moon" do
    assert_equal 0, sky_at("2026-10-24 05:30")[:progress]
    assert_equal 50, sky_at("2026-10-24 13:00")[:progress]
    assert_equal 100, sky_at("2026-10-24 20:29")[:progress].round(-1)
    assert_equal 50, sky_at("2026-10-24 01:00")[:progress]
  end
end
