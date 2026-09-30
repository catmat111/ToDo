class ProfilesController < ApplicationController
  PROFILE_FIELDS = %w[name email_address avatar_url objective theme timezone].freeze

  before_action :set_user

  def show
    @calendar_connection = @user.google_calendar
    @other_sessions_count = @user.sessions.where.not(id: Current.session.id).count
  end

  def edit
  end

  def update
    if @user.update(profile_params)
      changed = @user.saved_changes.keys & PROFILE_FIELDS
      AuditLog.record("user.updated", resource: @user, fields: changed) if changed.any?
      redirect_to profile_path, notice: "Perfil atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Quick toggle from the top bar: light → dark → system → light.
  def update_theme
    theme = params[:theme].to_s
    if User::THEMES.include?(theme) && @user.update(theme: theme)
      redirect_back_or_to root_path, status: :see_other
    else
      redirect_back_or_to root_path, status: :see_other, alert: "Tema inválido."
    end
  end

  def edit_password
  end

  def update_password
    current, password, confirmation = password_params.values_at(:current_password, :password, :password_confirmation)

    if !@user.authenticate(current.to_s)
      @user.errors.add(:current_password, "está incorreta")
    elsif password.blank?
      @user.errors.add(:password, :blank)
    elsif @user.update(password: password, password_confirmation: confirmation)
      @user.sessions.where.not(id: Current.session.id).destroy_all
      AuditLog.record("user.password_changed", resource: @user)
      return redirect_to profile_path, notice: "Password alterada. As outras sessões foram terminadas."
    end

    render :edit_password, status: :unprocessable_entity
  end

  def destroy
    unless @user.authenticate(params[:password].to_s)
      return redirect_to profile_path(anchor: "zona-de-perigo"), status: :see_other,
                         alert: "Password incorreta. A tua conta não foi eliminada."
    end

    delete_account!
    redirect_to new_session_path, status: :see_other, notice: "A tua conta e todos os teus dados foram eliminados."
  end

  private
    # A fresh copy of the signed-in user, so a failed update never leaks unsaved
    # values (theme, avatar, name) into the layout, which renders Current.user.
    def set_user
      @user = User.find(Current.user.id)
    end

    def profile_params
      params.expect(user: [ :name, :email_address, :avatar_url, :objective, :theme, :timezone ])
    end

    def password_params
      params.expect(user: [ :current_password, :password, :password_confirmation ])
    end

    def delete_account!
      User.transaction do
        AuditLog.record("user.deleted", resource: @user, user: nil, email: @user.email_address)
        @user.destroy!
      end
      cookies.delete(:session_id)
      Current.reset
    end
end
