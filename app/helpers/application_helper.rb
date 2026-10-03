# Shared view helpers are split by purpose (Rails includes every helper in every view):
#   IconsHelper       icon(:name)
#   NavigationHelper  masthead sections and sub-navigation
#   BadgesHelper      status_badge, priority_badge, tag_chip, progress_bar
#   FormattingHelper  format_datetime, format_date, relative_due
#   ThemeHelper       theme_toggle_button, theme_attribute
# Feature-specific helpers live in <feature>_helper.rb.
module ApplicationHelper
end
