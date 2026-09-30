class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "Redefinir a tua password do ToDo", to: user.email_address
  end
end
