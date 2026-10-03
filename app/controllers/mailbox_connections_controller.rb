# Connect Gmail (read-only), choose the label with job replies, sync, disconnect.
class MailboxConnectionsController < ApplicationController
  OAUTH_STATE_KEY = :gmail_oauth_state

  before_action :set_connection, only: %i[update sync destroy]

  def show
    @connection = Current.user.mailbox_connection
    @labels = fetch_labels if @connection&.active?
  end

  def create
    unless GmailClient.configured?
      return redirect_to mailbox_connection_path, alert: "A ligação à Google não está configurada neste servidor (GOOGLE_CLIENT_ID/SECRET)."
    end
    state = SecureRandom.urlsafe_base64(32)
    session[OAUTH_STATE_KEY] = state
    redirect_to GmailClient.new.authorization_url(state: state, redirect_uri: callback_mailbox_connection_url),
                allow_other_host: true
  end

  def callback
    expected = session.delete(OAUTH_STATE_KEY)
    unless expected.present? && params[:state].present? && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s)
      return redirect_to mailbox_connection_path, alert: "Pedido de autorização inválido ou expirado. Tenta novamente."
    end
    return redirect_to(mailbox_connection_path, alert: "Autorização cancelada — o Gmail não foi ligado.") if params[:error].present? || params[:code].blank?

    client = GmailClient.new
    tokens = client.exchange_code(code: params[:code].to_s, redirect_uri: callback_mailbox_connection_url)
    connection = Current.user.mailbox_connection || Current.user.build_mailbox_connection
    connection.update!(
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token.presence || connection.refresh_token,
      expires_at: tokens.expires_at,
      email_address: (client.profile(access_token: tokens.access_token)["emailAddress"] rescue nil),
      status: "active", last_error: nil
    )
    AuditLog.record("mailbox.connected", resource: connection)
    redirect_to mailbox_connection_path, notice: "Gmail ligado. Agora escolhe a etiqueta onde guardas as respostas."
  rescue GoogleCalendarClient::Error => e
    Rails.logger.warn("[gmail] OAuth callback failed: #{e.class}")
    redirect_to mailbox_connection_path, alert: "Não foi possível ligar ao Gmail. Tenta novamente."
  end

  # Choose the label.
  def update
    label = fetch_labels.find { |l| l["id"] == params[:label_id] }
    return redirect_to(mailbox_connection_path, alert: "Escolhe uma etiqueta da lista.") unless label

    @connection.update!(label_id: label["id"], label_name: label["name"], last_synced_at: nil)
    MailboxSyncJob.perform_later(@connection.id)
    redirect_to mailbox_connection_path, notice: "A ler a etiqueta «#{label["name"]}». As respostas aparecem em Emprego → Respostas."
  end

  def sync
    return redirect_to(mailbox_connection_path, alert: "Volta a ligar o Gmail primeiro.") unless @connection.active?
    MailboxSyncJob.perform_later(@connection.id)
    redirect_back_or_to email_messages_path, notice: "A verificar emails novos… atualiza a página dentro de instantes."
  end

  def destroy
    (GmailClient.new.revoke(token: @connection.refresh_token || @connection.access_token) rescue nil)
    @connection.destroy!
    AuditLog.record("mailbox.disconnected", resource: nil)
    redirect_to mailbox_connection_path, notice: "Gmail desligado. As respostas já lidas continuam guardadas."
  end

  private
    def set_connection
      @connection = Current.user.mailbox_connection or raise ActiveRecord::RecordNotFound
    end

    def fetch_labels
      connection = @connection || Current.user.mailbox_connection
      token = connection.token_expired? ? refresh(connection) : connection.access_token
      GmailClient.new.labels(access_token: token)
    rescue GoogleCalendarClient::AuthError
      connection.mark_error!("Autorização expirada — volta a ligar o Gmail.")
      []
    rescue GoogleCalendarClient::Error
      []
    end

    def refresh(connection)
      tokens = GmailClient.new.refresh(refresh_token: connection.refresh_token)
      connection.update!(access_token: tokens.access_token, expires_at: tokens.expires_at)
      tokens.access_token
    end
end
