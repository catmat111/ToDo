# Everything the "Hoje" page shows, computed for one user (plan §15).
# Only active (non-archived) tasks are considered; lists eager-load tags and
# subtasks so rendering stays free of N+1 queries.
class DashboardPresenter
  LIST_LIMIT = 6
  APPLICATIONS_LIMIT = 5
  REMINDERS_LIMIT = 5
  NOTIFICATIONS_LIMIT = 3

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

  def objective
    user.objective.presence
  end

  def today_label
    I18n.l(now.to_date, format: "%A, %-d de %B").upcase_first
  end

  # --- Task lists -----------------------------------------------------------

  # Still due later today (anything already past its deadline is in #overdue_tasks).
  def today_tasks
    @today_tasks ||= listed(today_scope.order(:due_at, priority: :desc))
  end

  def overdue_tasks
    @overdue_tasks ||= listed(overdue_scope.order(:due_at, priority: :desc))
  end

  def upcoming_tasks
    @upcoming_tasks ||= listed(upcoming_scope.order(:due_at, priority: :desc))
  end

  def in_progress_tasks
    @in_progress_tasks ||= listed(in_progress_scope.order(updated_at: :desc))
  end

  # --- Stats ------------------------------------------------------------------

  def today_count = @today_count ||= today_scope.count
  def overdue_count = @overdue_count ||= overdue_scope.count
  def upcoming_count = @upcoming_count ||= upcoming_scope.count
  def in_progress_count = @in_progress_count ||= in_progress_scope.count

  def completed_this_week_count
    @completed_this_week_count ||= user.tasks.completed.where(completed_at: now.beginning_of_week..now).count
  end

  def stats
    [
      { label: "Para hoje", value: today_count, modifier: "terracotta", icon: :calendar },
      { label: "Atrasadas", value: overdue_count, modifier: "mustard", icon: :clock },
      { label: "Em curso", value: in_progress_count, modifier: "olive", icon: :refresh },
      { label: "Concluídas esta semana", value: completed_this_week_count, modifier: "charcoal", icon: :check }
    ]
  end

  def any_tasks?
    return @any_tasks if defined?(@any_tasks)
    @any_tasks = user.tasks.active.exists?
  end

  # --- Other sections -------------------------------------------------------------

  def recent_applications
    @recent_applications ||= user.job_applications.in_progress.recent.limit(APPLICATIONS_LIMIT).to_a
  end

  def upcoming_reminders
    @upcoming_reminders ||= Reminder.upcoming(now)
                                    .joins(:task)
                                    .merge(user_open_tasks)
                                    .includes(:task)
                                    .limit(REMINDERS_LIMIT)
                                    .to_a
  end

  def unread_notifications
    @unread_notifications ||= user.notifications.unread.recent.limit(NOTIFICATIONS_LIMIT).includes(:notifiable).to_a
  end

  def unread_notifications_count
    @unread_notifications_count ||= user.notifications.unread.count
  end

  private
    def user_open_tasks
      Task.where(user_id: user.id).active.open
    end

    def base_scope
      user.tasks.active.open
    end

    def today_scope
      base_scope.where(due_at: now..now.end_of_day)
    end

    def overdue_scope
      base_scope.where(due_at: ...now)
    end

    def upcoming_scope
      base_scope.where(due_at: now.tomorrow.beginning_of_day..(now + 7.days).end_of_day)
    end

    def in_progress_scope
      user.tasks.active.in_progress
    end

    def listed(scope)
      scope.includes(:tags, :subtasks).limit(LIST_LIMIT).to_a
    end
end
