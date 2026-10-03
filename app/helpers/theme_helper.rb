# Light / dark / system theme (users.theme → <html data-theme>).
module ThemeHelper
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
