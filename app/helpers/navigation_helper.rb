# Masthead navigation: the four main sections, each with a small drop-down menu of its
# pages (the account pages hang off the avatar).
# To add a page: add its URL prefix to SECTIONS and a link to section_links.
module NavigationHelper
  # Top navigation: four sections; everything else lives in the section's menu.
  SECTIONS = [
    { key: :home, label: "Hoje", prefixes: [] },
    { key: :tasks, label: "Tarefas", prefixes: %w[/tasks /tags] },
    { key: :calendar, label: "Calendário", prefixes: %w[/calendar] },
    { key: :jobs, label: "Emprego", prefixes: %w[/applications /job_listings /job_searches /companies /contacts /replies /mailbox_connection] },
    { key: :account, label: nil, prefixes: %w[/profile /shares /notifications /history] }
  ].freeze

  def current_section
    return :home if request.path == "/"
    SECTIONS.find { |s| s[:prefixes].any? { |prefix| request.path.start_with?(prefix) } }&.dig(:key)
  end

  def main_sections
    paths = { home: root_path, tasks: tasks_path, calendar: calendar_path, jobs: job_applications_path }
    SECTIONS.select { |s| s[:label] }.map do |s|
      links = section_links(s[:key])
      { key: s[:key], label: s[:label], path: paths[s[:key]], active: current_section == s[:key],
        links: links, badge: links.sum { |link| link[:badge].to_i } }
    end
  end

  # The pages of one section, for its drop-down menu (empty for Hoje and Calendário).
  def section_links(section = current_section)
    items =
      case section
      when :tasks
        [ [ "Todas as tarefas", tasks_path, "/tasks" ], [ "Etiquetas", tags_path, "/tags" ] ]
      when :jobs
        [ [ "Candidaturas", job_applications_path, "/applications" ],
          [ "Estatísticas", application_stats_path, "/applications/stats" ], [ "Vagas", job_listings_path, "/job_listings" ],
          [ "Pesquisas", job_searches_path, "/job_searches" ], [ "Empresas", companies_path, "/companies" ],
          [ "Contactos", contacts_path, "/contacts" ],
          [ "Respostas", email_messages_path, "/replies", Current.user.email_messages.pending.count ] ]
      when :account
        [ [ "Perfil", profile_path, "/profile" ], [ "Notificações", notifications_path, "/notifications" ],
          [ "Partilhas", shares_path, "/shares", Current.user.received_shares.pending.count ],
          [ "Histórico", audit_logs_path, "/history" ] ]
      else
        []
      end
    # The most specific matching prefix wins (/applications/stats over /applications).
    active_prefix = items.map { |item| item[2] }.select { |prefix| request.path.start_with?(prefix) }.max_by(&:length)
    links = items.map do |label, path, prefix, badge|
      { label: label, path: path, active: prefix == active_prefix, badge: badge }
    end
    links << { label: "Sair", path: session_path, method: :delete, confirm: "Terminar sessão?" } if section == :account
    links
  end

  def unread_notifications_count
    return 0 unless Current.user
    @unread_notifications_count ||= Current.user.notifications.unread.count
  end
end
