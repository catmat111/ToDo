class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers (import maps, CSS nesting, :has); the minimums also
  # cover CSS light-dark(), which the theme tokens in application.css rely on.
  allow_browser versions: { chrome: 123, edge: 123, opera: 109, safari: 17.5, firefox: 120, ie: false }

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :use_user_time_zone
  helper_method :current_user

  private
    def current_user
      Current.user
    end

    # Datetimes are stored in UTC and shown/parsed in the user's own zone (plan §17).
    def use_user_time_zone(&)
      resume_session
      Time.use_zone(Current.user&.time_zone || Time.zone, &)
    end
end
