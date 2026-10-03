# Google Calendar v3 (plan §12): create / update / read / delete the events that
# mirror tasks. OAuth, HTTP and errors come from GoogleClient.
class GoogleCalendarClient < GoogleClient
  API_BASE = "https://www.googleapis.com/calendar/v3".freeze
  SCOPE = "https://www.googleapis.com/auth/calendar.events".freeze

  # --- Events --------------------------------------------------------------

  def insert_event(calendar_id:, access_token:, body:)
    request(:post, events_url(calendar_id), access_token: access_token, json: body)
  end

  def update_event(calendar_id:, access_token:, event_id:, body:, etag: nil)
    headers = etag.present? ? { "If-Match" => etag } : {}
    request(:put, event_url(calendar_id, event_id), access_token: access_token, json: body, headers: headers)
  end

  def get_event(calendar_id:, access_token:, event_id:)
    request(:get, event_url(calendar_id, event_id), access_token: access_token)
  end

  def delete_event(calendar_id:, access_token:, event_id:)
    request(:delete, event_url(calendar_id, event_id), access_token: access_token)
    true
  end

  private
    def events_url(calendar_id)
      "#{API_BASE}/calendars/#{ERB::Util.url_encode(calendar_id.presence || "primary")}/events"
    end

    def event_url(calendar_id, event_id)
      raise NotFoundError.new("Evento sem identificador", status: 404) if event_id.blank?
      "#{events_url(calendar_id)}/#{ERB::Util.url_encode(event_id)}"
    end
end
