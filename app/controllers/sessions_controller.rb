class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  before_action :redirect_if_authenticated, only: :new
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_session_path, alert: "Demasiadas tentativas de entrada. Tenta novamente daqui a alguns minutos."
  }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      AuditLog.record("user.signed_in", resource: user, user: user)
      redirect_to after_authentication_url, notice: "Olá de novo, #{user.first_name}!"
    else
      # Deliberately generic: never reveal whether the email address exists.
      redirect_to new_session_path, alert: "Email ou password incorretos."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: "Sessão terminada. Até breve!"
  end

  private
    def redirect_if_authenticated
      redirect_to root_path if authenticated?
    end
end
