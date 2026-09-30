class JobSearch < ApplicationRecord
  SOURCES = %w[linkedin indeed other].freeze
  SOURCE_LABELS = { "linkedin" => "LinkedIn", "indeed" => "Indeed", "other" => "Outra" }.freeze

  belongs_to :user
  has_many :job_filters, -> { order(:id) }, dependent: :destroy, inverse_of: :job_search
  has_many :job_listings, dependent: :nullify

  enum :source, SOURCES.index_by(&:itself), prefix: :source, validate: true

  normalizes :name, with: ->(value) { value.strip }
  normalizes :query, with: ->(value) { value.strip.presence }

  validates :name, presence: true, length: { maximum: 100 }
  validates :query, length: { maximum: 200 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(active: :desc, name: :asc) }

  def self.source_label(source)
    SOURCE_LABELS.fetch(source.to_s, source.to_s.humanize)
  end

  def source_label
    self.class.source_label(source)
  end

  def allowed_filter_keys
    JobFilter::ALLOWED_KEYS.fetch(source.to_s, [])
  end

  # Filters kept from another source are ignored when the URL is built.
  def unsupported_filters
    job_filters.select(&:persisted?).reject { |filter| allowed_filter_keys.include?(filter.key) }
  end

  # External URL for this search with every filter applied (plan §11, flow C).
  def search_url
    JobSearches::Sources.for(self).url
  end
end
