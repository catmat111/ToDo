class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update destroy]

  def index
    @sort = params[:sort] == "name" ? "name" : "applications"
    @companies = Current.user.companies
                        .left_joins(:job_applications).select("companies.*, COUNT(job_applications.id) AS applications_count")
                        .group("companies.id")
    @companies = if @sort == "name"
      @companies.alphabetical
    else
      @companies.order(Arel.sql("applications_count DESC")).alphabetical
    end
    @companies = @companies.where("LOWER(companies.name) LIKE ?", "%#{Company.sanitize_sql_like(params[:q].downcase)}%") if params[:q].present?
  end

  def show
    @applications = @company.job_applications.recent
    @contacts = @company.contacts
  end

  def new
    @company = Current.user.companies.new
  end

  def create
    @company = Current.user.companies.new(company_params)
    if @company.save
      redirect_to @company, notice: "Empresa criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @company.update(company_params)
      redirect_to @company, notice: "Empresa atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @company.destroy!
    redirect_to companies_path, notice: "Empresa eliminada. As candidaturas e contactos foram mantidos.", status: :see_other
  end

  private
    def set_company
      @company = Current.user.companies.find(params[:id])
    end

    def company_params
      params.expect(company: [ :name, :website, :location, :notes ])
    end
end
