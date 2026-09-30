class Tag < ApplicationRecord
  # Palette swatches offered in the tag form (the app's own colours plus two neutrals).
  COLORS = %w[#9C5D3C #6E6B41 #B07E1E #382C23 #8A7F6A #B5835A].freeze
  COLOR_NAMES = {
    "#9C5D3C" => "Terracota", "#6E6B41" => "Verde-oliva", "#B07E1E" => "Mostarda",
    "#382C23" => "Castanho-carvão", "#8A7F6A" => "Taupe", "#B5835A" => "Caramelo"
  }.freeze

  belongs_to :user
  has_many :task_tags, dependent: :destroy
  has_many :tasks, through: :task_tags

  normalizes :name, with: ->(n) { n.squish }
  normalizes :color, with: ->(c) { c.strip.upcase.presence }

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :color, format: { with: /\A#\h{6}\z/, message: "tem de ser uma cor hexadecimal (ex.: #9C5D3C)" },
                    allow_blank: true

  scope :alphabetical, -> { order(Arel.sql("LOWER(tags.name)")) }

  # Adds a +tasks_count+ column with the number of non-archived tasks using each tag.
  scope :with_task_counts, -> {
    joins("LEFT JOIN task_tags ON task_tags.tag_id = tags.id")
      .joins("LEFT JOIN tasks ON tasks.id = task_tags.task_id AND tasks.archived_at IS NULL")
      .select("tags.*, COUNT(tasks.id) AS tasks_count")
      .group("tags.id")
  }

  def self.color_name(hex)
    COLOR_NAMES.fetch(hex.to_s.upcase, hex.to_s.upcase)
  end

  def tasks_count
    has_attribute?(:tasks_count) ? self[:tasks_count].to_i : tasks.active.count
  end

  def palette_color?
    color.blank? || COLORS.include?(color)
  end
end
