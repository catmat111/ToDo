# Small UI pieces: status/priority badges, tag chips and progress bars.
module BadgesHelper
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

  def progress_bar(percent, label: nil)
    percent = percent.to_i.clamp(0, 100)
    tag.div(class: "progress", role: "progressbar", "aria-valuenow": percent, "aria-valuemin": 0,
            "aria-valuemax": 100, "aria-label": label || "Progresso") do
      tag.span(class: "progress__bar", style: "width: #{percent}%")
    end
  end
end
