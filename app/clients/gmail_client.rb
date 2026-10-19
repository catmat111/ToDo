# Read-only Gmail: list the user's labels and read messages from one of them —
# never send, change or delete. OAuth, HTTP and errors come from GoogleClient
# (same Google Cloud project / GOOGLE_CLIENT_ID as the calendar).
class GmailClient < GoogleClient
  READ_SCOPE = "https://www.googleapis.com/auth/gmail.readonly".freeze
  SCOPE = "#{READ_SCOPE} email".freeze
  GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me".freeze
  BODY_LIMIT = 4000

  # Google lets the user untick Gmail on the consent screen; the token then works but
  # can't read mail. +granted_scope+ is the "scope" of the token response (nil = unknown).
  def self.can_read_mail?(granted_scope)
    granted_scope.nil? || granted_scope.split.include?(READ_SCOPE)
  end

  def profile(access_token:)
    request(:get, "#{GMAIL_API}/profile", access_token: access_token)
  end

  # [{ "id" => "Label_12", "name" => "Candidaturas" }, …] — user labels only.
  def labels(access_token:)
    data = request(:get, "#{GMAIL_API}/labels", access_token: access_token)
    Array(data["labels"]).select { |label| label["type"] == "user" }
                         .map { |label| label.slice("id", "name") }
                         .sort_by { |label| label["name"].downcase }
  end

  # Message ids in a label, newest first (optionally only after a date).
  def message_ids(access_token:, label_id:, after: nil, max: 100)
    query = { labelIds: label_id, maxResults: max }
    query[:q] = "after:#{after.to_i}" if after
    data = request(:get, "#{GMAIL_API}/messages?#{URI.encode_www_form(query)}", access_token: access_token)
    Array(data["messages"]).map { |message| message["id"] }
  end

  # { id:, from_name:, from_email:, subject:, received_at:, text: }
  def message(access_token:, id:)
    data = request(:get, "#{GMAIL_API}/messages/#{id}?format=full", access_token: access_token)
    headers = Array(data.dig("payload", "headers")).to_h { |h| [ h["name"].downcase, h["value"] ] }
    from_name, from_email = parse_from(headers["from"].to_s)
    {
      id: data["id"],
      from_name: from_name, from_email: from_email,
      subject: headers["subject"].to_s,
      received_at: (Time.zone.at(data["internalDate"].to_i / 1000) if data["internalDate"]),
      text: plain_text(data["payload"]).presence || data["snippet"].to_s
    }
  end

  private
    def parse_from(value)
      if (match = value.match(/\A\s*"?([^"<]*?)"?\s*<([^>]+)>/))
        [ match[1].strip.presence, match[2].strip.downcase ]
      else
        [ nil, value.strip.downcase ]
      end
    end

    # First text/plain part (or HTML stripped of tags), decoded and trimmed.
    def plain_text(part)
      return "" if part.nil?
      if part["mimeType"] == "text/plain" && part.dig("body", "data")
        return decode(part.dig("body", "data"))
      end
      parts = Array(part["parts"])
      parts.each { |p| (text = plain_text(p)).present? && (return text) }
      html = parts.find { |p| p["mimeType"] == "text/html" } || (part if part["mimeType"] == "text/html")
      html&.dig("body", "data") ? ActionController::Base.helpers.strip_tags(decode(html.dig("body", "data"))).squish : ""
    end

    def decode(data)
      Base64.urlsafe_decode64(data).force_encoding("UTF-8").scrub.first(BODY_LIMIT)
    rescue ArgumentError
      ""
    end
end
