# A person (recruiter, interviewer…) the user deals with, optionally at a company.
class Contact < ApplicationRecord
  belongs_to :user
  belongs_to :company, optional: true
  has_many :job_applications, dependent: :nullify

  normalizes :name, with: ->(n) { n.squish }
  normalizes :email, with: ->(e) { e.strip.downcase.presence }
  normalizes :linkedin_url, with: ->(u) { u.strip.presence }

  validates :name, presence: true, length: { maximum: 200 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :linkedin_url, format: { with: %r{\Ahttps?://\S+\z}i, message: "tem de começar por http:// ou https://" },
                           allow_blank: true
  validates :notes, length: { maximum: 10_000 }
  validate :company_belongs_to_user

  scope :alphabetical, -> { order(Arel.sql("LOWER(contacts.name)")) }

  def label
    [ name, role.presence, company&.name ].compact.join(" · ")
  end

  private
    def company_belongs_to_user
      return if company.nil?
      errors.add(:company, "tem de ser tua") if company.user_id != user_id
    end
end
