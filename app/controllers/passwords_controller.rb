class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_password_path, alert: "Demasiados pedidos. Tenta novamente daqui a alguns minutos."
  }

  def new
  end

  def create
    if user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
      PasswordsMailer.reset(user).deliver_later
    end

    # Same answer whether or not the address exists, so accounts can't be enumerated.
    redirect_to new_session_path,
                notice: "Se existir uma conta com esse email, vais receber instruções para redefinir a password."
  end

  def edit
  end

  def update
    if params[:password].blank?
      @user.errors.add(:password, :blank)
      render :edit, status: :unprocessable_entity
    elsif @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      AuditLog.record("user.password_reset", resource: @user, user: @user)
      redirect_to new_session_path, notice: "A tua password foi redefinida. Já podes entrar."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: "O link para redefinir a password é inválido ou expirou. Pede um novo."
    end
end
