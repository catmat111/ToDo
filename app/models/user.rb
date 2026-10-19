class User < ApplicationRecord
  THEMES = %w[light dark system].freeze

  AVATAR_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  AVATAR_MAX_SIZE = 5.megabytes

  has_secure_password
  # Uploaded profile photo (Active Storage). avatar_url remains as an alternative.
  has_one_attached :avatar
  validate :avatar_is_a_small_image
  has_many :sessions, dependent: :destroy

  has_many :tasks, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :links, dependent: :destroy
  has_many :job_searches, dependent: :destroy
  has_many :job_listings, dependent: :destroy
  has_many :job_applications, dependent: :destroy
  has_many :companies, dependent: :destroy
  has_many :contacts, dependent: :destroy
  has_one :mailbox_connection, dependent: :destroy
  has_many :email_messages, dependent: :destroy
  has_many :calendar_connections, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :sent_shares, class_name: "Share", foreign_key: :sender_id, dependent: :destroy, inverse_of: :sender
  has_many :received_shares, class_name: "Share", foreign_key: :recipient_id, dependent: :destroy, inverse_of: :recipient
  has_many :audit_logs, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.strip }
  normalizes :avatar_url, with: ->(url) { User.direct_image_url(url) }

  GIPHY_PAGE = %r{\Ahttps?://(?:www\.)?giphy\.com/(?:embed|gifs)/(?:[\w-]*-)?(\w+)/?\z}i

  # Giphy page/embed links point to an HTML page, not an image; turn them into the GIF itself.
  def self.direct_image_url(url)
    url = url.to_s.strip
    (id = url[GIPHY_PAGE, 1]) ? "https://media.giphy.com/media/#{id}/giphy.gif" : url.presence
  end

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :theme, inclusion: { in: THEMES }
  validates :timezone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name } } }
  validates :avatar_url, format: { with: %r{\Ahttps?://\S+\z}i }, length: { maximum: 2000 }, allow_blank: true
  validates :objective, length: { maximum: 2000 }
  validates :follow_up_after_days, numericality: { only_integer: true, in: 0..90 }

  def time_zone
    ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["Europe/Lisbon"]
  end

  private def avatar_is_a_small_image
    return unless avatar.attached?
    errors.add(:avatar, "tem de ser uma imagem PNG, JPG, WebP ou GIF") unless avatar.blob.content_type.in?(AVATAR_TYPES)
    errors.add(:avatar, "tem de ter no máximo 5 MB") if avatar.blob.byte_size > AVATAR_MAX_SIZE
  end

  def first_name
    name.to_s.split.first
  end

  def google_calendar
    calendar_connections.find_by(provider: "google")
  end
end
