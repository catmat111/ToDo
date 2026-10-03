class ContactsController < ApplicationController
  before_action :set_contact, only: %i[edit update destroy follow_up]

  def index
    @contacts = Current.user.contacts.includes(:company).alphabetical
  end

  def new
    @contact = Current.user.contacts.new(company: own_company(params[:company_id]))
  end

  def create
    @contact = Current.user.contacts.new(contact_params)
    if @contact.save
      redirect_to(@contact.company || contacts_path, notice: "Contacto criado.")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to(@contact.company || contacts_path, notice: "Contacto atualizado.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy!
    redirect_back_or_to contacts_path, notice: "Contacto eliminado.", status: :see_other
  end

  # "Enviar follow-up": a task (due in 2 days) reminding who to write to.
  def follow_up
    application = Current.user.job_applications.find_by(id: params[:job_application_id])
    task = Current.user.tasks.create!(
      title: "Follow-up com #{@contact.name}#{" — #{application.title}" if application}".truncate(200),
      description: [ ("Email: #{@contact.email}" if @contact.email), ("Telefone: #{@contact.phone}" if @contact.phone) ].compact.join("\n"),
      task_type: "job", job_application: application, due_at: 2.days.from_now.change(hour: 10)
    )
    redirect_to edit_task_path(task), notice: "Tarefa de follow-up criada — ajusta a data se precisares."
  end

  private
    def set_contact
      @contact = Current.user.contacts.find(params[:id])
    end

    def own_company(id)
      Current.user.companies.find_by(id: id)
    end

    # company_id is only accepted if it is one of the user's companies.
    def contact_params
      attrs = params.expect(contact: [ :name, :role, :email, :phone, :linkedin_url, :notes, :company_id ])
      attrs[:company_id] = own_company(attrs[:company_id])&.id if attrs.key?(:company_id)
      attrs
    end
end
