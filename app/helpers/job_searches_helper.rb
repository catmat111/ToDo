module JobSearchesHelper
  # <span class="badge job-source job-source--linkedin">LinkedIn</span>
  def job_source_badge(source)
    tag.span(JobSearch.source_label(source), class: "badge job-source job-source--#{source.to_s.dasherize}")
  end

  def job_search_state_badge(job_search)
    if job_search.active?
      tag.span("Ativa", class: "badge badge--active")
    else
      tag.span("Em pausa", class: "badge badge--archived")
    end
  end

  # Chip such as "Recência: Última semana" or "Exclui: estágio".
  def job_filter_chip(filter)
    text = if filter.excludes?
      "Sem #{filter.value_label}"
    elsif filter.operator == "contains"
      "#{filter.label} contém #{filter.value_label}"
    else
      "#{filter.label}: #{filter.value_label}"
    end
    classes = [ "chip", "job-filter-chip", ("job-filter-chip--excludes" if filter.excludes?) ]
    tag.span(text, class: classes, title: "#{filter.label} · #{filter.operator_label} · #{filter.value_label}")
  end

  def job_filter_key_options(job_search)
    job_search.allowed_filter_keys.map { |key| [ JobFilter::KEY_LABELS.fetch(key, key.humanize), key ] }
  end

  def job_filter_operator_options
    JobFilter::OPERATOR_LABELS.map { |value, label| [ label, value ] }
  end

  def job_source_options
    JobSearch::SOURCE_LABELS.map { |value, label| [ label, value ] }
  end

  def job_filter_datalist_prefix(job_search)
    "job-filter-suggestions-#{job_search.id}"
  end

  def job_filter_datalist_id(job_search, key)
    "#{job_filter_datalist_prefix(job_search)}-#{key}"
  end

  def job_last_run(job_search)
    job_search.last_run_at ? "Aberta há #{time_ago_in_words(job_search.last_run_at)}" : "Ainda não foi aberta"
  end

  def job_listings_count_label(count)
    case count
    when 0 then "Sem vagas guardadas"
    when 1 then "1 vaga guardada"
    else "#{count} vagas guardadas"
    end
  end

  # The "Abrir pesquisa" button: POST to #run, opened in a new tab with Turbo disabled
  # so the browser follows the redirect to the external site.
  def run_job_search_button(job_search, label: "Abrir pesquisa", css: "btn btn--primary btn--sm")
    adapter = JobSearches::Sources.for(job_search)
    button_to run_job_search_path(job_search), class: css,
              title: "Abrir no #{adapter.label} (novo separador)",
              form: { target: "_blank", data: { turbo: false } } do
      safe_join([ icon(:external), tag.span(label), tag.span(" (abre num novo separador)", class: "sr-only") ])
    end
  end
end
