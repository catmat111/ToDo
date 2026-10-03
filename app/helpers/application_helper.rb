module ApplicationHelper
  ICONS = {
    home: "M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10",
    tasks: "M9 11l3 3 8-8M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h9",
    calendar: "M8 2v4M16 2v4M3 9h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
    briefcase: "M9 6V4h6v2M3 7h18v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V7zM3 12h18",
    search: "M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.35-4.35",
    list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
    bell: "M18 8a6 6 0 1 0-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0",
    settings: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z",
    tag: "M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8zM7 7h.01",
    plus: "M12 5v14M5 12h14",
    check: "M20 6L9 17l-5-5",
    clock: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20zM12 6v6l4 2",
    link: "M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.8 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7",
    trash: "M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6",
    edit: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
    archive: "M21 8v13H3V8M1 3h22v5H1zM10 12h4",
    external: "M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6M15 3h6v6M10 14L21 3",
    user: "M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z",
    logout: "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9",
    history: "M3 3v5h5M3.05 13A9 9 0 1 0 6 5.3L3 8M12 7v5l4 2",
    refresh: "M23 4v6h-6M1 20v-6h6M3.5 9a9 9 0 0 1 14.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0 0 20.5 15",
    menu: "M3 12h18M3 6h18M3 18h18",
    sun: "M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10zM12 1v2M12 21v2M4.2 4.2l1.4 1.4M18.4 18.4l1.4 1.4M1 12h2M21 12h2M4.2 19.8l1.4-1.4M18.4 5.6l1.4-1.4",
    moon: "M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z",
    monitor: "M4 4h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1zM8 20h8M12 16v4"
  }.freeze

  # Inline stroke icon; decorative unless a +title+ is given.
  def icon(name, size: 18, title: nil, **options)
    path = ICONS.fetch(name.to_sym)
    options[:class] = [ "icon", options[:class] ].compact.join(" ")
    aria = title ? { role: "img", "aria-label": title } : { "aria-hidden": "true" }
    content_tag(:svg, tag.path(d: path), viewBox: "0 0 24 24", width: size, height: size, fill: "none",
                stroke: "currentColor", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round",
                **aria, **options)
  end

  def nav_link_to(label, path, icon_name, badge: nil, match: nil)
    active = match ? request.path.start_with?(match) : current_page?(path)
    link_to path, class: [ "nav__link", ("is-active" if active) ], "aria-current": (active ? "page" : nil) do
      # A pre-rendered badge (e.g. the live notifications counter) is used as-is.
      badge_tag = badge.is_a?(ActiveSupport::SafeBuffer) ? badge : (tag.span(badge, class: "nav__badge") if badge.to_i.positive?)
      safe_join([ icon(icon_name), tag.span(label, class: "nav__label"), badge_tag ].compact)
    end
  end

  # Top navigation: four sections; everything else lives in the section's sub-nav.
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
      { label: s[:label], path: paths[s[:key]], active: current_section == s[:key] }
    end
  end

  # Second row of links for the current section (empty on the home page).
  def section_links
    items =
      case current_section
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
    links << { label: "Sair", path: session_path, method: :delete, confirm: "Terminar sessão?" } if current_section == :account
    links
  end

  STATUS_LABELS = {
    "pending" => "Pendente", "in_progress" => "Em curso", "completed" => "Concluída", "cancelled" => "Cancelada",
    "active" => "Ativa", "error" => "Erro", "revoked" => "Revogada", "synced" => "Sincronizado"
  }.freeze

  # <span class="badge badge--completed">Concluída</span>
  def status_badge(status, label = nil)
    label ||= STATUS_LABELS[status.to_s] || JobApplication::STATUS_LABELS[status.to_s] || status.to_s.humanize
    tag.span(label, class: "badge badge--#{status.to_s.dasherize}")
  end

  def priority_badge(task)
    return if task.priority.to_i.zero?
    tag.span(task.priority_label.capitalize, class: "badge badge--priority-#{task.priority}")
  end

  def tag_chip(tag_record)
    tag.span(tag_record.name, class: "chip", style: ("--chip-color: #{tag_record.color}" if tag_record.color.present?))
  end

  def format_datetime(time, format: :short)
    return "—" if time.blank?
    all_day?(time) ? l(time.in_time_zone.to_date, format: :long) : l(time.in_time_zone, format: format)
  end

  def format_date(date, format: :default)
    date.present? ? l(date.to_date, format: format) : "—"
  end

  # "hoje às 14:00", "amanhã", "há 3 dias"… for due dates.
  # A deadline at 23:59 means "some time that day" (no specific hour) — e.g. tasks
  # added from the quick-add post-it. Such dates are shown without a time.
  def all_day?(time)
    time.present? && time.in_time_zone.strftime("%H:%M") == "23:59"
  end

  def relative_due(time)
    return "sem prazo" if time.blank?
    t = time.in_time_zone
    today = Time.zone.today
    hour = all_day?(t) ? "" : " às #{l(t, format: '%H:%M')}"
    case t.to_date
    when today then "hoje#{hour}"
    when today + 1 then "amanhã#{hour}"
    when today - 1 then "ontem"
    else
      return l(t.to_date, format: "%-d %b") if all_day?(t)
      t.future? ? "em #{time_ago_in_words(t)}" : "há #{time_ago_in_words(t)}"
    end
  end

  def progress_bar(percent, label: nil)
    percent = percent.to_i.clamp(0, 100)
    tag.div(class: "progress", role: "progressbar", "aria-valuenow": percent, "aria-valuemin": 0,
            "aria-valuemax": 100, "aria-label": label || "Progresso") do
      tag.span(class: "progress__bar", style: "width: #{percent}%")
    end
  end

  def unread_notifications_count
    return 0 unless Current.user
    @unread_notifications_count ||= Current.user.notifications.unread.count
  end

  THEME_CYCLE = {
    "light" => { next: "dark", icon: :sun, label: "Tema claro (mudar para escuro)" },
    "dark" => { next: "system", icon: :moon, label: "Tema escuro (mudar para automático)" },
    "system" => { next: "light", icon: :monitor, label: "Tema automático (mudar para claro)" }
  }.freeze

  # Top-bar button that cycles the signed-in user's theme.
  def theme_toggle_button
    step = THEME_CYCLE.fetch(theme_attribute, THEME_CYCLE["system"])
    button_to theme_profile_path, method: :patch, params: { theme: step[:next] },
              class: "btn btn--ghost btn--icon", title: step[:label], form: { data: { turbo: false } } do
      icon step[:icon], title: step[:label]
    end
  end

  def theme_attribute
    Current.user&.theme.presence || "system"
  end
end
