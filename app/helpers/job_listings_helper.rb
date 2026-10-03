module JobListingsHelper
  def job_listing_discovered(listing)
    "Descoberta há #{time_ago_in_words(listing.discovered_at)}"
  end

  def job_listing_subtitle(listing)
    [ listing.company_name, listing.location ].compact_blank.join(" · ").presence || listing.host
  end

  def job_listing_state_options
    [ [ "Todas", "" ], [ "Já guardadas como candidatura", "saved" ], [ "Ainda sem candidatura", "new" ] ]
  end

  def job_listing_external_link(listing, label: "Abrir vaga", css: "btn btn--outline btn--sm")
    link_to listing.url, class: css, target: "_blank", rel: "noopener noreferrer" do
      safe_join([ icon(:external), tag.span(label), tag.span(" (abre num novo separador)", class: "sr-only") ])
    end
  end

  def job_listing_filters_applied?
    params.values_at(:q, :source, :job_search_id, :state, :work_mode, :min_salary).any?(&:present?)
  end
end
