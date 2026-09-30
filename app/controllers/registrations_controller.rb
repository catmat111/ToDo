class RegistrationsController < ApplicationController
  DEFAULT_TIMEZONE = "Europe/Lisbon".freeze

  allow_unauthenticated_access
  before_action :redirect_if_authenticated
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_registration_path, alert: "Demasiadas tentativas de registo. Tenta novamente daqui a alguns minutos."
  }

  def new
    @user = User.new(timezone: DEFAULT_TIMEZONE)
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for @user
      AuditLog.record("user.registered", resource: @user, user: @user)
      redirect_to root_path, notice: "Bem-vindo(a) ao ToDo, #{@user.first_name}! A tua conta foi criada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def registration_params
      params.expect(user: [ :name, :email_address, :password, :password_confirmation, :timezone ])
    end

    def redirect_if_authenticated
      redirect_to root_path if authenticated?
    end
end
