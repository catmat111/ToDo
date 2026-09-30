module AuditLogsHelper
  AUDIT_ACTION_LABELS = {
    "user.registered" => "Criaste a tua conta",
    "user.signed_in" => "Iniciaste sessão",
    "user.updated" => "Atualizaste o perfil",
    "user.password_changed" => "Alteraste a password",
    "user.password_reset" => "Redefiniste a password por email",
    "user.deleted" => "Eliminaste a conta",
    "task.created" => "Criaste uma tarefa",
    "task.updated" => "Editaste uma tarefa",
    "task.started" => "Começaste uma tarefa",
    "task.completed" => "Concluíste uma tarefa",
    "task.reopened" => "Reabriste uma tarefa",
    "task.cancelled" => "Cancelaste uma tarefa",
    "task.archived" => "Arquivaste uma tarefa",
    "task.unarchived" => "Desarquivaste uma tarefa",
    "task.deleted" => "Eliminaste uma tarefa",
    "job_application.created" => "Criaste uma candidatura",
    "job_application.updated" => "Editaste uma candidatura",
    "job_application.status_changed" => "Mudaste o estado de uma candidatura",
    "job_application.deleted" => "Eliminaste uma candidatura",
    "job_search.created" => "Criaste uma pesquisa de emprego",
    "job_search.run" => "Executaste uma pesquisa de emprego",
    "job_search.deleted" => "Eliminaste uma pesquisa de emprego",
    "job_listing.created" => "Adicionaste uma vaga",
    "job_listing.deleted" => "Eliminaste uma vaga",
    "calendar.connected" => "Ligaste o Google Calendar",
    "calendar.disconnected" => "Desligaste o Google Calendar",
    "calendar.sync_failed" => "A sincronização com o Google Calendar falhou"
  }.freeze

  AUDIT_DOMAIN_ICONS = {
    "user" => :user, "task" => :tasks, "tag" => :tag, "job_application" => :briefcase,
    "job_search" => :search, "job_listing" => :list, "calendar" => :calendar
  }.freeze

  AUDIT_RESOURCE_NAMES = {
    "User" => "Conta", "Task" => "Tarefa", "Tag" => "Etiqueta", "JobApplication" => "Candidatura",
    "JobSearch" => "Pesquisa", "JobListing" => "Vaga", "CalendarConnection" => "Google Calendar"
  }.freeze

  AUDIT_METADATA_LABELS = {
    "email" => "Email", "title" => "Título", "name" => "Nome", "status" => "Estado", "count" => "Total",
    "found" => "Encontradas", "created" => "Novas", "error" => "Erro", "message" => "Mensagem"
  }.freeze

  AUDIT_SCOPE_TABS = {
    nil => "Tudo", "conta" => "Conta", "tarefas" => "Tarefas", "emprego" => "Emprego", "calendario" => "Calendário"
  }.freeze

  # "task.completed" => "Concluíste uma tarefa"; unknown keys fall back to a readable form.
  def audit_action_label(action)
    AUDIT_ACTION_LABELS.fetch(action.to_s) { action.to_s.tr("._", "  ").squish.humanize }
  end

  def audit_icon(action)
    AUDIT_DOMAIN_ICONS.fetch(action.to_s.split(".").first, :history)
  end

  # Colour family used by the timeline: account, tasks, jobs, calendar or other.
  def audit_domain(action)
    case action.to_s.split(".").first
    when "user" then "account"
    when "task", "tag" then "tasks"
    when /\Ajob_/ then "jobs"
    when "calendar" then "calendar"
    else "other"
    end
  end

  def audit_day_label(date)
    today = Time.zone.today
    case date
    when today then "Hoje"
    when today - 1 then "Ontem"
    else format_date(date, format: :long)
    end
  end

  # Link to the affected record when it still exists; a muted label when it was deleted.
  # +resources+ is the { [type, id] => record } map preloaded (and ownership-scoped) by the controller.
  def audit_resource_link(log, resources)
    return if log.resource_type.blank?

    if log.resource_type == "User"
      return unless log.resource_id == Current.user&.id
      return link_to("O teu perfil", profile_path, class: "history-entry__resource")
    end

    record = resources[[ log.resource_type, log.resource_id ]]
    path = record && audit_resource_path(record)
    kind = AUDIT_RESOURCE_NAMES.fetch(log.resource_type, log.resource_type.titleize)

    if path
      link_to(path, class: "history-entry__resource") do
        safe_join([ tag.span("#{kind}:", class: "muted"), " ", audit_resource_name(record) ])
      end
    else
      tag.span("#{kind} (já não existe)", class: "history-entry__resource muted")
    end
  end

  # "de Pendente para Concluída · Campos: Nome, Tema"
  def audit_details(log)
    metadata = log.metadata.is_a?(Hash) ? log.metadata.stringify_keys : {}
    parts = []

    if metadata.key?("from") || metadata.key?("to")
      parts << "de #{audit_value_label(metadata['from'])} para #{audit_value_label(metadata['to'])}"
    end
    if metadata["fields"].present?
      fields = Array(metadata["fields"]).map { |field| User.human_attribute_name(field) }
      parts << "Campos: #{fields.join(', ')}"
    end
    metadata.except("from", "to", "fields").each do |key, value|
      next if value.blank? || value.is_a?(Hash)
      label = AUDIT_METADATA_LABELS.fetch(key) { key.humanize }
      parts << "#{label}: #{Array(value).join(', ').truncate(120)}"
    end

    parts.join(" · ").presence
  end

  private
    def audit_resource_path(record)
      case record
      when Task then task_path(record)
      when Tag then edit_tag_path(record)
      when JobApplication then job_application_path(record)
      when JobSearch then job_search_path(record)
      when JobListing then job_listing_path(record)
      when CalendarConnection then calendar_connection_path
      end
    end

    def audit_resource_name(record)
      (record.try(:title) || record.try(:name)).presence || AUDIT_RESOURCE_NAMES.fetch(record.class.name, "##{record.id}")
    end

    def audit_value_label(value)
      return "—" if value.blank?
      ApplicationHelper::STATUS_LABELS[value.to_s] || JobApplication::STATUS_LABELS[value.to_s] || value.to_s.humanize
    end
end
