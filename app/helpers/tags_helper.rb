module TagsHelper
  HEX_COLOR = /\A#\h{6}\z/

  # Inline custom property for a tag colour; only well-formed hex values reach the style attribute.
  def tag_color_style(color)
    "--chip-color: #{color}" if color.to_s.match?(HEX_COLOR)
  end

  def swatch_style(color)
    "--swatch-color: #{color}" if color.to_s.match?(HEX_COLOR)
  end

  # "Sem tarefas ativas", "1 tarefa ativa", "4 tarefas ativas"
  def tag_tasks_count_label(count)
    case count.to_i
    when 0 then "Sem tarefas ativas"
    when 1 then "1 tarefa ativa"
    else "#{count} tarefas ativas"
    end
  end

  def tags_summary(tags)
    total = tags.size
    return "Organiza as tuas tarefas por contexto." if total.zero?
    in_use = tags.count { |t| t.tasks_count.positive? }
    "#{total} #{total == 1 ? 'etiqueta' : 'etiquetas'} · #{in_use} em uso"
  end

  def tag_color_name(color)
    color.present? ? Tag.color_name(color) : "Sem cor"
  end

  # Value for the "custom colour" radio/picker: the tag's own colour when it is not in the palette.
  def custom_tag_color(tag_record)
    color = tag_record.color.to_s
    color.match?(HEX_COLOR) && !Tag::COLORS.include?(color) ? color : Tag::COLORS.first
  end
end
