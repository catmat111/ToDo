class JobSearchesController < ApplicationController
  before_action :set_job_search, only: %i[show edit update destroy run]

  def index
    @job_searches = Current.user.job_searches.includes(:job_filters).ordered
    @listing_counts = Current.user.job_listings.where.not(job_search_id: nil).group(:job_search_id).count
  end

  def show
    @job_filters = @job_search.job_filters.to_a
    @job_filter = JobFilter.new(operator: "equals")
    @job_listings = @job_search.job_listings.recent.limit(20)
  end

  def new
    @job_search = Current.user.job_searches.new(source: params[:source].presence_in(JobSearch::SOURCES) || "linkedin")
  end

  def create
    @job_search = Current.user.job_searches.new(job_search_params)

    if @job_search.save
      AuditLog.record("job_search.created", resource: @job_search, source: @job_search.source)
      redirect_to @job_search, notice: "Pesquisa criada. Adiciona filtros e abre-a no #{adapter_label}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @job_search.update(job_search_params)
      AuditLog.record("job_search.updated", resource: @job_search, changes: @job_search.saved_changes.keys - %w[updated_at])
      redirect_to(params[:return_to] == "index" ? job_searches_path : @job_search, notice: update_notice)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @job_search.destroy!
    AuditLog.record("job_search.destroyed", resource: @job_search, name: @job_search.name)
    redirect_to job_searches_path, notice: "Pesquisa eliminada. As vagas encontradas continuam guardadas.", status: :see_other
  end

  # Opens the external site with every filter applied (the view submits this in a new tab).
  # LinkedIn searches ask once whether the user has the LinkedIn app, remember the answer
  # and from then on open the app (yes) or the website (no).
  def run
    remember_linkedin_app if @job_search.source == "linkedin"
    return render :linkedin_choice if @job_search.source == "linkedin" && Current.user.linkedin_app.nil?

    if @job_search.source == "linkedin" && Current.user.linkedin_app?
      # A redirect to linkedin:// would fail inside the service worker (it only fetches http),
      # so a page hands the link to the app instead.
      @app_url = JobSearches::Runner.call(@job_search, app: true)
      @web_url = JobSearches::Sources.for(@job_search).url
      render :open_linkedin_app
    else
      redirect_to JobSearches::Runner.call(@job_search), allow_other_host: true, status: :see_other
    end
  end

  private
    def set_job_search
      @job_search = Current.user.job_searches.find(params[:id])
    end

    def job_search_params
      params.expect(job_search: [ :name, :source, :query, :active ])
    end

    def remember_linkedin_app
      answer = { "yes" => true, "no" => false }[params[:linkedin_app].to_s]
      Current.user.update_column(:linkedin_app, answer) unless answer.nil?
    end

    def adapter_label
      JobSearches::Sources.for(@job_search).label
    end

    def update_notice
      if @job_search.saved_change_to_active?
        @job_search.active? ? "Pesquisa reativada." : "Pesquisa em pausa."
      else
        "Pesquisa atualizada."
      end
    end
end
