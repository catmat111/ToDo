class JobListing < ApplicationRecord
  include Compensation
  SOURCES = %w[linkedin indeed other].freeze
  TRACKING_PARAMS = %w[ref refid trk trackingid fbclid gclid].freeze

  belongs_to :user
  belongs_to :job_search, optional: true
  has_many :job_applications, dependent: :nullify
  has_many :shares, as: :shareable, dependent: :nullify

  enum :source, SOURCES.index_by(&:itself), prefix: :source, validate: true

  normalizes :title, :company_name, :location, with: ->(value) { value.squish.presence }
  normalizes :url, :external_id, with: ->(value) { value.strip.presence }

  before_validation :assign_normalized_url
  before_validation -> { self.discovered_at ||= Time.current }

  validates :title, presence: true, length: { maximum: 200 }
  validates :company_name, :location, length: { maximum: 200 }
  validates :external_id, length: { maximum: 200 }
  validates :url, presence: true, format: { with: %r{\Ahttps?://[^\s]+\z}i, message: "tem de começar por http:// ou https://" }
  validates :normalized_url, presence: true, uniqueness: { scope: :user_id, message: "já está guardado noutra vaga" }
  validates :external_id, uniqueness: { scope: [ :user_id, :source ] }, allow_blank: true
  validate :job_search_belongs_to_user

  scope :recent, -> { order(discovered_at: :desc, id: :desc) }
  scope :matching, ->(term) {
    pattern = "%#{sanitize_sql_like(term.to_s.strip.downcase)}%"
    where("LOWER(job_listings.title) LIKE :pattern OR LOWER(job_listings.company_name) LIKE :pattern", pattern: pattern)
  }
  scope :with_application_for, ->(user) { where(id: user.job_applications.where.not(job_listing_id: nil).select(:job_listing_id)) }
  scope :without_application_for, ->(user) { where.not(id: user.job_applications.where.not(job_listing_id: nil).select(:job_listing_id)) }

  # Strips tracking params, fragments, trailing slashes and case differences so the
  # same job found twice collapses to one row.
  def self.normalize_url(raw)
    uri = URI.parse(raw.to_s.strip)
    return raw.to_s.strip.downcase unless uri.is_a?(URI::HTTP) && uri.host

    params = URI.decode_www_form(uri.query.to_s).reject do |k, _|
      k.start_with?("utm_") || TRACKING_PARAMS.include?(k.downcase)
    end
    host = uri.host.downcase.delete_prefix("www.")
    path = uri.path.to_s.sub(%r{/+\z}, "")
    query = params.sort.any? ? "?#{URI.encode_www_form(params.sort)}" : ""
    "https://#{host}#{path}#{query}"
  rescue URI::InvalidURIError, ArgumentError
    raw.to_s.strip.downcase
  end

  def application_for(user)
    job_applications.find_by(user: user)
  end

  def source_label
    JobSearch.source_label(source)
  end

  def host
    URI.parse(url.to_s).host&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  private
    def assign_normalized_url
      self.normalized_url = self.class.normalize_url(url) if url.present?
    end

    def job_search_belongs_to_user
      return if job_search.nil?
      errors.add(:job_search, "tem de pertencer ao mesmo utilizador") if job_search.user_id != user_id
    end
end
