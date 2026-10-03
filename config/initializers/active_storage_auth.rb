# Active Storage's direct-upload endpoint (POST /rails/active_storage/direct_uploads) is
# public by default, so anyone could create files on the server. The app only uploads
# through its own forms (profile photo), so require a signed-in user there too.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.class_eval do
    include Authentication

    private
      # JSON endpoint: answer 401 instead of redirecting to the login page.
      def request_authentication
        head :unauthorized
      end
  end
end
