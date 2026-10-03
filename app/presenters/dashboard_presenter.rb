# Everything the "Hoje" page shows, for one user: greeting, today's list (overdue
# first), the next few days and how many applications are still in progress.
# Only active (non-archived), open tasks are listed; lists eager-load what the rows
# render (blockers for the "bloqueada" badge) so the page has no N+1 queries.
class DashboardPresenter
  TODAY_LIMIT = 30
  UPCOMING_LIMIT = 5
  UPCOMING_DAYS = 7

  attr_reader :user, :now

  def initialize(user, now: Time.current)
    @user = user
    @now = now.in_time_zone(user.time_zone)
  end

  def greeting
    salutation =
      case now.hour
      when 5..11 then "Bom dia"
      when 12..19 then "Boa tarde"
      else "Boa noite"
      end
    [ salutation, user.first_name ].compact_blank.join(", ")
  end

  def today_label
    I18n.l(now.to_date, format: "%A, %-d de %B").upcase_first
  end

  # Overdue tasks first, then the ones due later today.
  def today_tasks
    @today_tasks ||= listed(open_tasks.where(due_at: ..now.end_of_day).order(:due_at, priority: :desc), TODAY_LIMIT)
  end

  def upcoming_tasks
    @upcoming_tasks ||= listed(
      open_tasks.where(due_at: now.tomorrow.beginning_of_day..(now + UPCOMING_DAYS.days).end_of_day).order(:due_at, priority: :desc),
      UPCOMING_LIMIT
    )
  end

  def open_applications_count
    @open_applications_count ||= user.job_applications.in_progress.count
  end

  private
    def open_tasks
      user.tasks.active.open
    end

    def listed(scope, limit)
      scope.includes(:blockers).limit(limit).to_a
    end
end
