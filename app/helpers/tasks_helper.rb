module TasksHelper
  STATUS_ACTIONS = {
    "in_progress" => { action: :start, label: "Iniciar", icon: :clock, style: "btn--outline" },
    "completed" => { action: :complete, label: "Concluir", icon: :check, style: "btn--secondary" },
    "cancelled" => { action: :cancel, label: "Cancelar tarefa", icon: nil, style: "btn--ghost" },
    "pending" => { action: :reopen, label: "Reabrir", icon: :refresh, style: "btn--outline" }
  }.freeze

  DUE_FILTER_LABELS = { "today" => "Hoje", "overdue" => "Em atraso", "week" => "Esta semana", "none" => "Sem prazo" }.freeze
  SORT_LABELS = { "due" => "Prazo", "priority" => "Prioridade", "recent" => "Mais recentes", "title" => "Título" }.freeze

  def task_type_badge(task)
    tag.span(task.type_label, class: "badge badge--type")
  end

  def task_type_options
    Task::TYPES.map { |type| [ Task.type_label(type), type ] }
  end

  def task_priority_options
    Task::PRIORITIES.keys.map { |value| [ Task.priority_label(value), value ] }
  end

  def task_status_options(task)
    ([ task.status_in_database || task.status ] + Task::TRANSITIONS.fetch(task.status_in_database.to_s, []))
      .uniq.map { |status| [ Task.status_label(status), status ] }
  end

  def task_status_filter_options
    [ [ "Em aberto", "open" ] ] + Task::STATUSES.map { |status| [ Task.status_label(status), status ] }
  end

  def task_due_filter_options
    DUE_FILTER_LABELS.map { |value, label| [ label, value ] }
  end

  # Other active filters as removable chips: [ label, params without that filter ].
  def task_filter_chips(filter)
    label_for = ->(options, value) { options.find { |_, v| v.to_s == value.to_s }&.first }
    chips = []
    chips << [ "“#{filter.q}”", filter.to_params(q: nil) ] if filter.q
    chips << [ label_for.call(task_status_filter_options, filter.status), filter.to_params(status: nil) ] if filter.status
    chips << [ label_for.call(task_type_options, filter.task_type), filter.to_params(task_type: nil) ] if filter.task_type
    chips << [ "Prioridade #{label_for.call(task_priority_options, filter.priority).to_s.downcase}", filter.to_params(priority: nil) ] if filter.priority
    chips << [ label_for.call(task_due_filter_options, filter.due), filter.to_params(due: nil) ] if filter.due
    chips << [ "Com subtarefas", filter.to_params(subtasks: nil) ] if filter.subtasks?
    chips
  end

  def task_sort_options
    SORT_LABELS.map { |value, label| [ label, value ] }
  end

  def task_frequency_options
    TaskRecurrence::FREQUENCIES.map { |frequency| [ TaskRecurrence.frequency_label(frequency), frequency ] }
  end

  # Due date for lists: highlighted when overdue, nothing for closed tasks without a date.
  def task_due(task)
    return if task.due_at.blank?
    if task.overdue?
      tag.span(class: "badge badge--overdue") { safe_join([ icon(:clock, size: 13), "Em atraso · #{relative_due(task.due_at)}" ], " ") }
    else
      tag.span(class: "task-due") { safe_join([ icon(:clock, size: 13), relative_due(task.due_at) ], " ") }
    end
  end

  # "2/5 subtarefas" + small bar, only for parents.
  def task_subtask_progress(task)
    done, total = task.progress
    return if total.zero?
    tag.span(class: "task-progress") do
      safe_join([ progress_bar(task.progress_percent, label: "Subtarefas concluídas"),
                  tag.span("#{done}/#{total}", class: "task-progress__count") ])
    end
  end

  # Round check button: completes an open task, reopens a closed one.
  def task_toggle_button(task)
    if task.open?
      button_to complete_task_path(task), method: :patch, class: "task-check",
                title: "Concluir", "aria-label": "Concluir «#{task.title}»" do
        icon(:check, size: 14)
      end
    else
      button_to reopen_task_path(task), method: :patch, class: "task-check task-check--done",
                title: "Reabrir", "aria-label": "Reabrir «#{task.title}»" do
        icon(:check, size: 14)
      end
    end
  end

  # One button per status the task can move to from here.
  def task_status_buttons(task, except: [])
    safe_join((task.allowed_transitions - except).map do |status|
      config = STATUS_ACTIONS.fetch(status)
      button_to [ config[:action], task ], method: :patch, class: "btn btn--sm #{config[:style]}" do
        safe_join([ (icon(config[:icon], size: 15) if config[:icon]), config[:label] ].compact, " ")
      end
    end)
  end

  # The parent only when it belongs to the same user (a rejected foreign parent_task_id
  # must never leak its title back into the re-rendered form).
  def task_visible_parent(task)
    parent = task.parent_task
    parent if parent&.persisted? && parent.user_id == task.user_id
  end

  # Inline error under a form field, linked through aria-describedby by the caller.
  def task_field_error(record, attribute, id: nil)
    messages = record.errors.full_messages_for(attribute)
    return if messages.empty?
    tag.p(messages.to_sentence, class: "field__error", id: id)
  end

  def task_job_application_options(job_applications)
    job_applications.map { |application| [ [ application.title, application.company_name ].compact_blank.join(" — "), application.id ] }
  end

  def task_recurrence_summary(recurrence)
    unit = { "daily" => %w[dia dias], "weekly" => %w[semana semanas],
             "monthly" => %w[mês meses], "yearly" => %w[ano anos] }.fetch(recurrence.frequency)
    text = if recurrence.interval == 1
      { "daily" => "Todos os dias", "weekly" => "Todas as semanas",
        "monthly" => "Todos os meses", "yearly" => "Todos os anos" }.fetch(recurrence.frequency)
    else
      "A cada #{recurrence.interval} #{unit.last}"
    end
    recurrence.ends_at ? "#{text}, até #{format_date(recurrence.ends_at)}" : text
  end

  def task_delete_confirmation(task)
    subtasks = task.subtasks.size
    extra = subtasks.positive? ? " e as suas #{subtasks} subtarefa#{'s' unless subtasks == 1}" : ""
    "Eliminar «#{task.title}»#{extra}? Esta ação não pode ser desfeita. " \
      "Se só a queres tirar da lista, arquiva-a em vez disso."
  end
end
