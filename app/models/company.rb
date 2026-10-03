# A company the user applies to. Applications are linked automatically by the
# company name typed in the application form (see JobApplication#link_company).
class Company < ApplicationRecord
  belongs_to :user
  has_many :contacts, -> { order(:name) }, dependent: :nullify
  has_many :job_applications, dependent: :nullify

  normalizes :name, with: ->(n) { n.squish }
  normalizes :website, with: ->(w) { w.strip.presence }

  validates :name, presence: true, length: { maximum: 200 },
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :website, format: { with: %r{\Ahttps?://\S+\z}i, message: "tem de começar por http:// ou https://" },
                      allow_blank: true
  validates :notes, length: { maximum: 10_000 }

  scope :alphabetical, -> { order(Arel.sql("LOWER(companies.name)")) }

  # Case-insensitive lookup used when linking applications by name.
  def self.named(name)
    where("LOWER(companies.name) = ?", name.to_s.squish.downcase)
  end
end
