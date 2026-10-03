class SearchesController < ApplicationController
  def show
    @search = GlobalSearch.new(Current.user, params[:q])
  end
end
