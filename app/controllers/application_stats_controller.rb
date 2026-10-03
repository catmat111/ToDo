class ApplicationStatsController < ApplicationController
  def show
    @stats = JobApplications::Stats.new(Current.user)
  end
end
