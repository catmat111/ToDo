class DashboardController < ApplicationController
  def show
    @dashboard = DashboardPresenter.new(Current.user)
  end
end
