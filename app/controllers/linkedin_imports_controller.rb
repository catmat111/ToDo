# Upload page for LinkedIn's "Job Applications.csv" (see JobApplications::LinkedinImport).
class LinkedinImportsController < ApplicationController
  rate_limit to: 10, within: 10.minutes, only: :create,
             with: -> { redirect_to new_linkedin_import_path, alert: "Demasiadas importações seguidas. Espera uns minutos." }
  MAX_SIZE = 5.megabytes

  def new
  end

  def create
    file = params[:file]
    return redirect_to(new_linkedin_import_path, alert: "Escolhe o ficheiro CSV.") if file.blank?
    return redirect_to(new_linkedin_import_path, alert: "O ficheiro é demasiado grande (máx. 5 MB).") if file.size > MAX_SIZE

    @summary = JobApplications::LinkedinImport.call(user: Current.user, io: file)
    render :show
  rescue ArgumentError, CSV::MalformedCSVError => e
    redirect_to new_linkedin_import_path, alert: "Não foi possível importar: #{e.message}."
  end
end
