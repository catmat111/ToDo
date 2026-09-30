# Month / week view of the current user's tasks, plus the Google sync status.
class CalendarController < ApplicationController
  def show
    @period = Calendar::Period.from_params(params, today: Time.zone.today)
    @agenda = Calendar::Agenda.new(user: Current.user, period: @period)
    @connection = Current.user.google_calendar
    @configured = GoogleCalendarClient.configured?
  end
end
