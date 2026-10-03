class JobListingsController < ApplicationController
  PER_PAGE = 30

  before_action :set_job_listing, only: %i[show destroy]

  def index
    @job_searches = Current.user.job_searches.ordered
    @page = [ params[:page].to_i, 1 ].max
    scope = filtered_listings
    @total_count = scope.count
    @job_listings = scope.includes(:job_search).recent.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @next_page = @page + 1 if @total_count > @page * PER_PAGE
    @applications_by_listing = Current.user.job_applications
      .where(job_listing_id: @job_listings.map(&:id)).index_by(&:job_listing_id)
  end

  def show
    @job_application = @job_listing.application_for(Current.user)
  end

  def new
    job_search = Current.user.job_searches.find_by(id: params[:job_search_id]) if params[:job_search_id].present?
    @job_listing = Current.user.job_listings.new(job_search: job_search)
    @selected_source = job_search&.source
    @job_searches = Current.user.job_searches.ordered
  end

  def create
    result = JobListings::Importer.call(user: Current.user, attributes: job_listing_params)
    @job_listing = result.listing

    if result.created?
      redirect_to @job_listing, notice: "Vaga guardada."
    elsif result.duplicate?
      redirect_to @job_listing, notice: "Esta vaga já estava guardada."
    else
      @selected_source = job_listing_params[:source]
      @job_searches = Current.user.job_searches.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @job_listing.destroy!
    AuditLog.record("job_listing.destroyed", resource: @job_listing, title: @job_listing.title)
    redirect_to job_listings_path, notice: "Vaga eliminada.", status: :see_other
  end

  private
    def set_job_listing
      @job_listing = Current.user.job_listings.find(params[:id])
    end

    def job_listing_params
      params.expect(job_listing: [ :url, :title, :company_name, :location, :source, :job_search_id,
                                   :published_at, :external_id, :description,
                                   :work_mode, :salary_min, :salary_max, :salary_period ])
    end

    def filtered_listings
      scope = Current.user.job_listings
      scope = scope.matching(params[:q]) if params[:q].present?
      scope = scope.where(source: params[:source]) if params[:source].presence_in(JobListing::SOURCES)
      scope = scope.where(job_search_id: params[:job_search_id]) if params[:job_search_id].present?
      scope = scope.with_work_mode(params[:work_mode]) if params[:work_mode].presence_in(Compensation::WORK_MODES.keys)
      scope = scope.paying_at_least(params[:min_salary]) if params[:min_salary].to_i.positive?
      case params[:state]
      when "saved" then scope.with_application_for(Current.user)
      when "new" then scope.without_application_for(Current.user)
      else scope
      end
    end
end
