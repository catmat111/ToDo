module AccountHelper
  THEME_LABELS = { "light" => "Claro", "dark" => "Escuro", "system" => "Automático (segue o sistema)" }.freeze

  # Portuguese names for the zones our users are most likely to pick.
  TIMEZONE_NAMES = {
    "Lisbon" => "Lisboa", "Azores" => "Açores", "Cape Verde Is." => "Cabo Verde", "London" => "Londres",
    "Madrid" => "Madrid", "Paris" => "Paris", "Berlin" => "Berlim", "Brasilia" => "Brasília",
    "Luanda" => "Luanda", "Maputo" => "Maputo"
  }.freeze

  def theme_options
    User::THEMES.map { |theme| [ theme_label(theme), theme ] }
  end

  def theme_label(theme)
    THEME_LABELS.fetch(theme.to_s, theme.to_s.humanize)
  end

  # [ [ "(GMT+00:00) Edimburgo, Lisboa…", "Europe/Lisbon" ], … ] — one entry per IANA identifier
  # (the value stored in users.timezone), ordered by UTC offset.
  def timezone_options
    AccountHelper.timezone_options
  end

  def timezone_label(identifier)
    timezone_options.to_h(&:reverse).fetch(identifier.to_s, identifier.to_s)
  end

  def self.timezone_options
    @timezone_options ||= ActiveSupport::TimeZone.all.group_by { |zone| zone.tzinfo.name }.map do |identifier, zones|
      names = zones.map { |zone| TIMEZONE_NAMES.fetch(zone.name, zone.name) }
      [ "(GMT#{zones.first.formatted_offset}) #{names.join(", ")}", identifier ]
    end.freeze
  end

  # Round avatar with the user's photo or initial. Only absolute http(s) URLs are rendered,
  # so an invalid value being re-shown on a failed form never reaches image_tag's asset lookup.
  def user_avatar(user, size: nil)
    tag.span(class: [ "avatar", ("avatar--#{size}" if size) ], "aria-hidden": "true") do
      if user.avatar_url.to_s.match?(%r{\Ahttps?://\S+\z}i)
        image_tag(user.avatar_url, alt: "", referrerpolicy: "no-referrer")
      else
        user.name.to_s.first.to_s.upcase
      end
    end
  end

  CALENDAR_STATUS_LABELS = { "active" => "Ligado", "error" => "Com erro", "revoked" => "Acesso revogado" }.freeze

  def profile_calendar_badge(connection)
    return tag.span("Não ligado", class: "badge") if connection.nil?
    status_badge(connection.status, CALENDAR_STATUS_LABELS.fetch(connection.status, connection.status.humanize))
  end
end
