module Inbox
  # Turns email bodies into plain readable text: drops <style>/<script> blocks and
  # leftover CSS rules, removes tags, decodes HTML entities (&aacute; → á) and squishes
  # whitespace.
  module Text
    CSS_RULE = /[.#@]?[\w\-.:#\s,>]+\s*\{[^{}]*\}/

    def self.clean(text)
      text = text.to_s
      text = text.gsub(%r{<(style|script)[^>]*>.*?</\1>}mi, " ")
      # Nokogiri removes tags AND decodes every named entity (CGI only knows &amp; &lt; …).
      text = Nokogiri::HTML5.fragment(text).text.tr(" ​", "  ") # nbsp, zero-width space
      text.gsub(CSS_RULE, " ").squish
    end
  end
end
