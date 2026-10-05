class ApplicationMailer < ActionMailer::Base
  # Sender shown to users, e.g. "Tu Do <no-reply@o-teu-dominio.pt>". With Gmail SMTP it
  # must be your own Gmail address (Gmail rewrites any other sender).
  default from: ENV.fetch("MAILER_FROM", "Tu Do <no-reply@todo.local>")
  layout "mailer"
end
