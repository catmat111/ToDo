module JobApplicationsHelper
  JOB_APPLICATION_TRANSITION_HINTS = {
    "applied" => "Registar que enviaste a candidatura.",
    "interview" => "Marcar uma entrevista com a empresa.",
    "offer" => "Recebeste uma proposta.",
    "rejected" => "A empresa não avançou. Este estado é final.",
    "withdrawn" => "Desististe desta candidatura. Este estado é final."
  }.freeze

  JOB_LISTING_SOURCE_LABELS = { "linkedin" => "LinkedIn", "indeed" => "Indeed", "itjobs" => "ITjobs", "other" => "Outra fonte" }.freeze

  def job_application_transition_label(job_application, to)
    return "Nova entrevista" if job_application.interview? && to.to_s == "interview"
    JobApplication.status_label(to)
  end

  def job_application_transition_hint(job_application, to)
    return "Registar mais uma ronda de entrevistas." if job_application.interview? && to.to_s == "interview"
    JOB_APPLICATION_TRANSITION_HINTS[to.to_s]
  end

  def job_application_transition_button_class(to)
    case to.to_s
    when "rejected", "withdrawn" then "btn btn--danger btn--sm"
    when "offer" then "btn btn--secondary btn--sm"
    else "btn btn--primary btn--sm"
    end
  end

  # Terminal states can't be undone, so ask first.
  def job_application_transition_confirm(to)
    return if JobApplication::TRANSITIONS.fetch(to.to_s, [ :open ]).any?
    "Marcar como «#{JobApplication.status_label(to)}»? Este estado é final e não pode ser revertido."
  end

  def job_application_status_options(selected = nil)
    options_for_select(
      [ [ "Todos os estados", "" ] ] + JobApplication::STATUSES.map { |status| [ JobApplication.status_label(status), status ] },
      selected
    )
  end

  def job_application_event_type_options(selected = nil)
    manual = JobApplicationEvent::MANUAL_TYPES.map { |type| [ JobApplicationEvent.label_for(type), type ] }
    statuses = JobApplication::STATUSES.map { |type| [ JobApplicationEvent.label_for(type), type ] }
    grouped_options_for_select({ "Registo" => manual, "Etapa" => statuses }, selected)
  end

  # "Enviada há 3 dias" / "Atualizada há 2 horas".
  def job_application_activity(job_application)
    if job_application.applied_at.present?
      "Enviada há #{time_ago_in_words(job_application.applied_at)}"
    else
      "Atualizada há #{time_ago_in_words(job_application.updated_at)}"
    end
  end

  def job_listing_source_label(source)
    JOB_LISTING_SOURCE_LABELS.fetch(source.to_s, source.to_s.humanize)
  end
end
