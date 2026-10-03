class ProfilesController < ApplicationController
  PROFILE_FIELDS = %w[name email_address avatar_url objective theme timezone follow_up_after_days].freeze

  before_action :set_user
  # These actions check the current password: slow down guessing.
  rate_limit to: 10, within: 3.minutes, only: %i[update update_password destroy],
             with: -> { redirect_to profile_path, alert: "Demasiadas tentativas. Espera uns minutos e tenta outra vez." }

  def show
    @calendar_connection = @user.google_calendar
    @other_sessions_count = @user.sessions.where.not(id: Current.session.id).count
  end

  def edit
  end

  def update
    new_photo = profile_params[:avatar].present?
    # Changing the login email needs the current password (otherwise anyone with an open
    # session could take over the account via "forgot password" on a new address).
    if email_change_without_password?
      @user.assign_attributes(profile_params.except(:avatar))
      @user.errors.add(:base, "Para mudares o email, confirma a tua password atual.")
      return render :edit, status: :unprocessable_entity
    end

    if @user.update(profile_params)
      # The last choice wins: an uploaded photo clears the link, a new link replaces the upload.
      if new_photo
        @user.update_column(:avatar_url, nil)
      elsif params[:remove_avatar] == "1" || (@user.saved_change_to_avatar_url? && @user.avatar_url.present?)
        @user.avatar.purge_later if @user.avatar.attached?
      end
      changed = @user.saved_changes.keys & PROFILE_FIELDS
      changed << "avatar" if new_photo || params[:remove_avatar] == "1"
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
      params.expect(user: [ :name, :email_address, :avatar_url, :avatar, :objective, :theme, :timezone, :follow_up_after_days ])
    end

    def email_change_without_password?
      new_email = profile_params[:email_address].to_s.strip.downcase
      new_email.present? && new_email != @user.email_address && !@user.authenticate(params[:current_password].to_s)
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
