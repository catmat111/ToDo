# The current user's Google Calendar connection (singular resource).
# OAuth tokens never reach the browser: only status information is rendered.
class CalendarConnectionsController < ApplicationController
  OAUTH_STATE_KEY = :google_calendar_oauth_state

  before_action :set_connection, only: %i[sync destroy]

  def show
    @connection = Current.user.google_calendar
    @configured = GoogleCalendarClient.configured?
    return unless @connection

    @event_counts = @connection.event_counts
    @problem_events = @connection.calendar_events.with_errors.includes(:task).order(updated_at: :desc).limit(20)
  end

  def create
    unless GoogleCalendarClient.configured?
      return redirect_to calendar_connection_path, alert: "A integração com o Google Calendar não está configurada neste servidor."
    end

    state = SecureRandom.urlsafe_base64(32)
    session[OAUTH_STATE_KEY] = state
    redirect_to Calendar.client.authorization_url(state: state, redirect_uri: callback_calendar_connection_url),
                allow_other_host: true
  end

  def callback
    expected_state = session.delete(OAUTH_STATE_KEY)

    unless valid_state?(expected_state, params[:state])
      return redirect_to calendar_connection_path, alert: "Pedido de autorização inválido ou expirado. Tenta ligar novamente."
    end
    if params[:error].present?
      message = params[:error] == "access_denied" ? "Autorização cancelada — a conta Google não foi ligada." : "A Google recusou o pedido de autorização."
      return redirect_to calendar_connection_path, alert: message
    end
    if params[:code].blank?
      return redirect_to calendar_connection_path, alert: "A Google não devolveu um código de autorização."
    end

    tokens = Calendar.client.exchange_code(code: params[:code].to_s, redirect_uri: callback_calendar_connection_url)
    Calendar::Connect.call(user: Current.user, tokens: tokens)
    redirect_to calendar_connection_path, notice: "Google Calendar ligado. A primeira sincronização já começou."
  rescue GoogleClient::Error => e
    Rails.logger.warn("[calendar] OAuth callback failed: #{e.class}")
    redirect_to calendar_connection_path, alert: "Não foi possível ligar ao Google Calendar. Tenta novamente."
  end

  def sync
    unless @connection.active?
      return redirect_to calendar_connection_path, alert: "A ligação precisa de ser renovada antes de sincronizar. Volta a ligar a conta Google."
    end

    resolve = params[:resolve] == "todo"
    CalendarSyncJob.perform_later(@connection.id, resolve_conflicts: resolve)
    AuditLog.record("calendar.sync_requested", resource: @connection, resolve_conflicts: resolve)
    notice = resolve ? "Sincronização agendada — os conflitos vão ser resolvidos com a versão do Tu Do." : "Sincronização agendada. Os eventos vão ser atualizados dentro de instantes."
    redirect_back_or_to calendar_connection_path, notice: notice
  end

  def destroy
    Calendar::Disconnect.call(@connection)
    redirect_to calendar_connection_path, notice: "Google Calendar desligado. Os eventos já criados continuam no teu calendário Google."
  end

  private
    def set_connection
      @connection = Current.user.calendar_connections.find_by!(provider: "google")
    end

    def valid_state?(expected, received)
      expected.present? && received.present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected.to_s, received.to_s)
    end
end
