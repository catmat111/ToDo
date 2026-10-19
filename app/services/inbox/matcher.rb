module Inbox
  # Finds which of the user's applications an email is about. Scores each open
  # application by: sender's domain vs company (website / name), company name in the
  # email, job title in the email, and the recruiter's email. Returns nil when unsure.
  class Matcher
    GENERIC_DOMAINS = %w[gmail.com outlook.com hotmail.com yahoo.com icloud.com sapo.pt
                         linkedin.com indeed.com itjobs.pt greenhouse.io lever.co workday.com myworkdayjobs.com
                         smartrecruiters.com teamtailor.com recruitee.com bamboohr.com].freeze
    MIN_SCORE = 3

    def self.call(user:, from_email:, subject:, text:)
      new(user:, from_email:, subject:, text:).call
    end

    def initialize(user:, from_email:, subject:, text:)
      @user = user
      @from_email = from_email.to_s.downcase
      @haystack = normalize("#{subject}\n#{text}")
      @domain = @from_email.split("@").last.to_s
    end

    def call
      candidates = @user.job_applications.includes(:company, :contact).order(updated_at: :desc).limit(300)
      best = candidates.map { |application| [ application, score(application) ] }.max_by(&:last)
      best && best.last >= MIN_SCORE ? best.first : nil
    end

    private
      def score(application)
        points = 0
        points += 6 if application.contact&.email.present? && application.contact.email == @from_email
        company = normalize(application.company_name)
        points += 4 if company.length >= 3 && @haystack.include?(company)
        points += 4 if company_domain?(application)
        title = normalize(application.title)
        points += 3 if title.length >= 5 && @haystack.include?(title)
        points += 1 if application.applied? || application.interview? # still waiting for news
        points
      end

      # "careers@acme.pt" matches ACME (by name) or the company's website domain.
      def company_domain?(application)
        return false if @domain.blank? || GENERIC_DOMAINS.any? { |generic| @domain.end_with?(generic) }
        website = application.company&.website.to_s
        site_host = URI.parse(website).host.to_s.delete_prefix("www.") rescue ""
        return true if site_host.present? && @domain.end_with?(site_host)
        name = normalize(application.company_name).delete(" ")
        name.length >= 3 && @domain.split(".").first(2).any? { |part| part.include?(name) || name.include?(part) && part.length >= 4 }
      end

      def normalize(text)
        I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9@. ]/, " ").squish
      end
  end
end
