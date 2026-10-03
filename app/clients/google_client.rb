require "net/http"
require "json"

# Shared base for the Google API clients (GoogleCalendarClient, GmailClient):
# OAuth2 (authorize / exchange / refresh / revoke), HTTP via Net::HTTP (no extra
# gems) and typed errors. Subclasses only declare their SCOPE and endpoints. Every failure is mapped to a typed error so callers
# can decide what to retry:
#
#   AuthError     -> 401 / invalid_grant: the user must reconnect (never retried)
#   NotFoundError -> 404 / 410: the remote event no longer exists
#   ConflictError -> 412: the event changed remotely (If-Match etag mismatch)
#   NetworkError  -> timeouts, connection failures, 429 and 5xx (safe to retry)
#
# Tokens are only ever sent in headers/bodies and never included in exception
# messages or #inspect output.
class GoogleClient
  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth".freeze
  TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  REVOKE_URL = "https://oauth2.googleapis.com/revoke".freeze
  # Space-separated OAuth scopes; each subclass sets its own.
  SCOPE = "".freeze

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  WRITE_TIMEOUT = 10

  class Error < StandardError
    attr_reader :status

    def initialize(message = nil, status: nil)
      @status = status
      super(message)
    end
  end
  class AuthError < Error; end
  class NotFoundError < Error; end
  class ConflictError < Error; end
  class NetworkError < Error; end
  class NotConfiguredError < Error; end

  # Result of a token exchange/refresh. #inspect never reveals the tokens.
  TokenSet = Data.define(:access_token, :refresh_token, :expires_at, :scope) do
    def inspect
      "#<GoogleClient::TokenSet expires_at: #{expires_at.inspect}, scope: #{scope.inspect}>"
    end
    alias_method :to_s, :inspect
  end

  # Minimal response value returned by transports: status code + raw body.
  Response = Data.define(:status, :body)

  NETWORK_ERRORS = [
    Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
    Errno::ETIMEDOUT, SocketError, IOError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
  ].freeze

  def self.config
    Rails.configuration.x.google
  end

  def self.configured?
    config.client_id.present? && config.client_secret.present?
  end

  # +transport+ is any callable (Net::HTTPRequest, URI) -> Response; injectable in tests.
  def initialize(client_id: self.class.config.client_id, client_secret: self.class.config.client_secret, transport: nil)
    @client_id = client_id
    @client_secret = client_secret
    @transport = transport || method(:net_http_transport)
  end

  def inspect
    "#<#{self.class.name} configured: #{configured?}>"
  end

  def configured?
    @client_id.present? && @client_secret.present?
  end

  # --- OAuth ---------------------------------------------------------------

  def authorization_url(state:, redirect_uri:)
    ensure_configured!
    query = URI.encode_www_form(
      client_id: @client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: self.class::SCOPE,
      access_type: "offline",
      prompt: "consent",
      include_granted_scopes: "true",
      state: state
    )
    "#{AUTH_URL}?#{query}"
  end

  def exchange_code(code:, redirect_uri:)
    ensure_configured!
    token_request(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
  end

  def refresh(refresh_token:)
    ensure_configured!
    raise AuthError, "Sem refresh token disponível" if refresh_token.blank?
    token_request(grant_type: "refresh_token", refresh_token: refresh_token)
  end

  # Revokes the grant. Google answers 400 for tokens that are already invalid;
  # callers treat revocation as best effort and rescue Error.
  def revoke(token:)
    return true if token.blank?
    request(:post, REVOKE_URL, form: { token: token })
    true
  end

  private
    def ensure_configured!
      raise NotConfiguredError, "Integração Google não configurada (GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET)" unless configured?
    end

    def token_request(**params)
      data = request(:post, TOKEN_URL, form: params.merge(client_id: @client_id, client_secret: @client_secret), token_endpoint: true)
      raise Error, "Resposta de token inválida" if data["access_token"].blank?

      TokenSet.new(
        access_token: data["access_token"],
        refresh_token: data["refresh_token"],
        expires_at: data["expires_in"].present? ? Time.current + data["expires_in"].to_i.seconds : nil,
        scope: data["scope"]
      )
    end

    def request(verb, url, access_token: nil, json: nil, form: nil, headers: {}, token_endpoint: false)
      uri = URI(url)
      req = build_request(verb, uri)
      req["Accept"] = "application/json"
      req["Authorization"] = "Bearer #{access_token}" if access_token
      headers.each { |name, value| req[name] = value }
      if form
        req.set_form_data(form)
      elsif json
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(json)
      end

      handle_response(@transport.call(req, uri), token_endpoint: token_endpoint)
    rescue *NETWORK_ERRORS => e
      raise NetworkError, "Falha de rede ao contactar a Google (#{e.class.name})"
    end

    def build_request(verb, uri)
      {
        get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete
      }.fetch(verb).new(uri)
    end

    def net_http_transport(req, uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, write_timeout: WRITE_TIMEOUT) do |http|
        http.request(req)
      end
      Response.new(status: response.code.to_i, body: response.body)
    end

    def handle_response(response, token_endpoint:)
      status = response.status.to_i
      data = parse_body(response.body)
      return data if status.between?(200, 299)

      reason = error_reason(data)
      message = "Google respondeu #{status}#{" (#{reason})" if reason}"

      raise error_class_for(status, reason, token_endpoint).new(message, status: status)
    end

    def error_class_for(status, reason, token_endpoint)
      case status
      when 401 then AuthError
      when 400 then token_endpoint && %w[invalid_grant unauthorized_client].include?(reason) ? AuthError : Error
      when 404, 410 then NotFoundError
      when 412 then ConflictError
      when 403 then %w[rateLimitExceeded userRateLimitExceeded].include?(reason) ? NetworkError : Error
      when 408, 429, 500..599 then NetworkError
      else Error
      end
    end

    def parse_body(body)
      return {} if body.blank?
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Only machine-readable reason codes are surfaced (never free text that could echo input).
    def error_reason(data)
      error = data["error"]
      reason = case error
      when String then error
      when Hash then error.dig("errors", 0, "reason") || error["status"]
      end
      reason.to_s[/\A[A-Za-z_]{1,64}\z/]
    end
end
