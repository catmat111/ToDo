# Be sure to restart your server when you modify this file.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self                                   # + nonce (see below) for importmap
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :https, :data, :blob             # avatars: any https URL; blob: = photo preview
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
    # Forms that redirect off-site: job searches open LinkedIn/Indeed/Google,
    # and "Ligar Google Calendar" goes to Google's OAuth page.
    policy.form_action :self, "https://www.linkedin.com", "https://pt.indeed.com",
                       "https://www.google.com", "https://accounts.google.com"
  end

  # Random nonce per request so the importmap <script> tags are allowed.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
