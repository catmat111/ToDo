class JobFiltersController < ApplicationController
  before_action :set_job_search
  before_action :set_job_filter, only: %i[update destroy]

  def create
    @job_filter = @job_search.job_filters.new(job_filter_params)

    if @job_filter.save
      AuditLog.record("job_search.filter_added", resource: @job_search, key: @job_filter.key, operator: @job_filter.operator)
      redirect_to job_search_path(@job_search, anchor: "filtros"), notice: "Filtro «#{@job_filter.label}» adicionado."
    else
      render_search_page
    end
  end

  def update
    if @job_filter.update(job_filter_params)
      AuditLog.record("job_search.filter_updated", resource: @job_search, key: @job_filter.key, operator: @job_filter.operator)
      redirect_to job_search_path(@job_search, anchor: "filtros"), notice: "Filtro «#{@job_filter.label}» atualizado."
    else
      @editing_filter = @job_filter
      render_search_page(new_filter: JobFilter.new(operator: "equals"))
    end
  end

  def destroy
    @job_filter.destroy!
    AuditLog.record("job_search.filter_removed", resource: @job_search, key: @job_filter.key)
    redirect_to job_search_path(@job_search, anchor: "filtros"), notice: "Filtro «#{@job_filter.label}» removido.",
                status: :see_other
  end

  private
    def set_job_search
      @job_search = Current.user.job_searches.find(params[:job_search_id])
    end

    def set_job_filter
      @job_filter = @job_search.job_filters.find(params[:id])
    end

    def job_filter_params
      params.expect(job_filter: [ :key, :operator, :value ])
    end

    # Re-renders the search page with the invalid filter and its errors.
    def render_search_page(new_filter: @job_filter)
      @job_search.job_filters.reset
      @job_filters = @job_search.job_filters.to_a
      @job_filter = new_filter
      @job_listings = @job_search.job_listings.recent.limit(20)
      render "job_searches/show", status: :unprocessable_entity
    end
end
