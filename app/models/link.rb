class Link < ApplicationRecord
  LINKABLE_TYPES = %w[Task JobApplication].freeze

  belongs_to :user
  belongs_to :linkable, polymorphic: true

  normalizes :url, with: ->(u) { u.strip }
  normalizes :label, with: ->(l) { l.squish.presence }

  validates :linkable_type, inclusion: { in: LINKABLE_TYPES }
  validates :url, presence: true, length: { maximum: 2000 },
                  format: { with: %r{\Ahttps?://[^\s]+\z}i, message: "tem de começar por http:// ou https://" }
  validates :label, length: { maximum: 100 }
  validate :linkable_belongs_to_user

  scope :chronological, -> { order(:created_at, :id) }

  def host
    URI.parse(url.to_s).host&.downcase&.delete_prefix("www.")
  rescue URI::InvalidURIError
    nil
  end

  def display_label
    label.presence || host || url
  end

  private
    def linkable_belongs_to_user
      return if linkable.nil?
      errors.add(:linkable, "tem de pertencer ao mesmo utilizador") if linkable.user_id != user_id
    end
end
