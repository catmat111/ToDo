module JobApplications
  # Daily (config/recurring.yml): for applications still "applied" with no news for the
  # user's follow_up_after_days, create one "Follow-up" task for today and notify.
  # Each application gets at most one automatic follow-up (follow_up_suggested_at), only
  # while it is still worth it (sent at most MAX_AGE ago), and the user gets ONE summary
  # notification per run instead of one per application.
  #
  #   JobApplications::FollowUps.call  # => number of follow-ups created
  class FollowUps
    MAX_AGE = 30.days
    # Created together with "applied" by imports; not news from the company.
    NOT_NEWS = %w[saved applied].freeze

    def self.call(now: Time.current)
      new(now:).call
    end

    def initialize(now:)
      @now = now
    end

    def call
      created = 0
      User.where("follow_up_after_days > 0").find_each do |user|
        done = due_for(user).select { |application| create_follow_up(user, application) }
        notify(user, done) if done.any?
        created += done.size
      end
      created
    end

    private
      def due_for(user)
        cutoff = @now - user.follow_up_after_days.days
        user.job_applications.applied.where(follow_up_suggested_at: nil).where(applied_at: (@now - MAX_AGE)...cutoff)
            .includes(:contact, :job_application_events)
            .reject { |application| news_since_sent?(application) }
      end

      # Anything in the history after sending (answer, note, follow-up…) counts as news.
      def news_since_sent?(application)
        application.job_application_events.any? do |event|
          NOT_NEWS.exclude?(event.event_type) && event.occurred_at >= application.applied_at
        end
      end

      def create_follow_up(user, application)
        Time.use_zone(user.time_zone) do
          ActiveRecord::Base.transaction do
            user.tasks.create!(
              title: "Follow-up: #{application.title}".truncate(200),
              description: description(user, application),
              task_type: "job", job_application: application,
              due_at: Time.zone.now.end_of_day.change(sec: 0) # "today", no specific hour
            )
            application.update_columns(follow_up_suggested_at: @now)
          end
        end
        true
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[follow_ups] application #{application.id}: #{e.message}")
        false
      end

      def notify(user, applications)
        names = applications.map { |a| a.company_name.presence || a.title }.uniq
        user.notifications.create!(
          notification_type: "application", notifiable: (applications.first if applications.one?),
          title: applications.one? ? "Sem resposta de #{names.first}" : "#{applications.size} candidaturas sem resposta",
          body: "Passaram #{user.follow_up_after_days} dias sem notícias de #{names.first(3).to_sentence(last_word_connector: " e ")}#{" e outras" if names.size > 3}. Criei tarefas de follow-up para hoje."
        )
      end

      def description(user, application)
        contact = application.contact
        lines = [ "Candidatura enviada a #{I18n.l(application.applied_at.in_time_zone(user.time_zone).to_date, format: :long)}, sem resposta desde então." ]
        lines << "Contacto: #{contact.name}#{" — #{contact.email}" if contact.email}" if contact
        lines.join("\n")
      end
  end
end
