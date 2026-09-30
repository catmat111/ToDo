class User < ApplicationRecord
  THEMES = %w[light dark system].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy

  has_many :tasks, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :links, dependent: :destroy
  has_many :job_searches, dependent: :destroy
  has_many :job_listings, dependent: :destroy
  has_many :job_applications, dependent: :destroy
  has_many :calendar_connections, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.strip }

  validates :email_address, presence: true, uniqueness: true,
                            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 100 }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :theme, inclusion: { in: THEMES }
  validates :timezone, inclusion: { in: ->(_) { ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name } } }
  validates :avatar_url, format: { with: %r{\Ahttps?://\S+\z}i }, length: { maximum: 2000 }, allow_blank: true
  validates :objective, length: { maximum: 2000 }

  def time_zone
    ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["Europe/Lisbon"]
  end

  def first_name
    name.to_s.split.first
  end

  def google_calendar
    calendar_connections.find_by(provider: "google")
  end
end
