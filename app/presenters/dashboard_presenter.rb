# Everything the "Hoje" page shows, for one user: greeting, today's list (overdue
# first), the next few days, how many applications are still in progress, and the
# backlog — each tag with its open tasks (undated ones included), in the left column.
# Only active (non-archived), open tasks are listed; lists eager-load what the rows
# render (blockers for the "bloqueada" badge) so the page has no N+1 queries.
class DashboardPresenter
  TODAY_LIMIT = 30
  UPCOMING_LIMIT = 5
  UPCOMING_DAYS = 7
  BACKLOG_PER_TAG = 6

  BacklogGroup = Data.define(:tag, :tasks, :total)

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

  # :morning, :afternoon or :night — the page's colours and icon follow it.
  def time_of_day
    case now.hour
    when 5..11 then :morning
    when 12..19 then :afternoon
    else :night
    end
  end

  # The header's sky: :dawn, :day, :dusk or :night, and where the sun (or moon) is on
  # its arc, 0..100 from rising to setting. app/javascript/controllers/sky_controller.js
  # does the same sums in the browser to keep the sky moving while the page is open.
  def sky
    hour = now.hour + now.min / 60.0
    phase = if hour >= 5.5 && hour < 8 then :dawn
    elsif hour >= 8 && hour < 18 then :day
    elsif hour >= 18 && hour < 20.5 then :dusk
    else :night
    end
    progress = if phase == :night
      ((hour >= 20.5 ? hour - 20.5 : hour + 3.5) / 9.0) # 20:30 → 05:30
    else
      (hour - 5.5) / 15.0 # 05:30 → 20:30
    end
    { phase: phase, progress: (progress.clamp(0, 1) * 100).round }
  end

  def completed_today_count
    @completed_today_count ||= user.tasks.active.where(completed_at: now.beginning_of_day..now.end_of_day).count
  end

  def overdue_count
    @overdue_count ||= today_tasks.count(&:overdue?)
  end

  # Share of today's tasks already done (0..100), nil when there was nothing for today.
  def today_progress
    total = completed_today_count + today_tasks.size
    total.zero? ? nil : (completed_today_count * 100.0 / total).round
  end

  # A short, kind line about how the day looks.
  def mood
    open = today_tasks.size
    if open.zero? && completed_today_count.positive? then "Tudo feito por hoje. Bom trabalho — merecias um chá."
    elsif open.zero? then "Dia tranquilo: nada marcado para hoje."
    elsif overdue_count.positive? then "#{overdue_count == 1 ? "Há uma coisa atrasada" : "Há #{overdue_count} coisas atrasadas"}. Uma de cada vez."
    elsif open == 1 then "Só uma coisa para hoje. Vai com calma."
    else "#{open} coisas para hoje. Uma de cada vez."
    end
  end

  def upcoming_by_day
    upcoming_tasks.group_by { |task| task.due_at.in_time_zone(user.time_zone).to_date }
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

  # One group per tag (alphabetical, empty ones too, so tasks can be added to them):
  # dated tasks first by date, then undated by priority.
  def backlog
    @backlog ||= begin
      tags = user.tags.alphabetical.to_a
      links = TaskTag.joins(:task).merge(open_tasks).where(tag_id: tags.map(&:id)).includes(task: :blockers)
      by_tag = links.group_by(&:tag_id).transform_values do |rows|
        rows.map(&:task).sort_by { |t| [ t.due_at ? 0 : 1, t.due_at.to_i, -t.priority.to_i, t.id ] }
      end
      tags.map do |tag|
        tasks = by_tag.fetch(tag.id, [])
        BacklogGroup.new(tag: tag, tasks: tasks.first(BACKLOG_PER_TAG), total: tasks.size)
      end
    end
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
