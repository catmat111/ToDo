module Tasks
  # Query object behind the task list filters.
  #
  #   filter = Tasks::Filter.new(Current.user, params)
  #   filter.tasks      # => current page (Array, at most PER_PAGE)
  #   filter.next_page? # => more results after this page?
  #   filter.to_params  # => sanitized filter params, safe to build links with
  #
  # Defaults: only root-level, non-archived tasks. A text search (q) looks at every level.
  class Filter
    PER_PAGE = 50
    DUE_OPTIONS = %w[today overdue week none].freeze
    SORTS = %w[due priority recent title].freeze
    KEYS = %i[q status task_type priority tag_id due sort archived subtasks].freeze

    attr_reader :q, :status, :task_type, :priority, :tag, :due, :sort, :page

    def initialize(user, params = {})
      @user = user
      # Every value is coerced/whitelisted below, so reading the raw hash is safe.
      params = (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h).symbolize_keys
      @q = params[:q].to_s.strip.first(100).presence
      @status = pick(params[:status], Task::STATUSES + [ "open" ])
      @task_type = pick(params[:task_type], Task::TYPES)
      @priority = pick(params[:priority], Task::PRIORITIES.keys.map(&:to_s))
      @tag = user.tags.find_by(id: params[:tag_id]) if params[:tag_id].to_s.match?(/\A\d+\z/)
      @due = pick(params[:due], DUE_OPTIONS)
      @sort = pick(params[:sort], SORTS) || "due"
      @archived = truthy?(params[:archived])
      @subtasks = truthy?(params[:subtasks])
      @page = [ params[:page].to_i, 1 ].max
    end

    def archived?
      @archived
    end

    def subtasks?
      @subtasks
    end

    # Any narrowing filter beyond the defaults (used for the "clear filters" link and empty states).
    def active?
      [ q, status, task_type, priority, tag, due ].any?(&:present?) || subtasks?
    end

    def scope
      scope = user.tasks
      scope = archived? ? scope.archived : scope.active
      scope = scope.root_level unless subtasks? || q
      scope = search(scope) if q
      scope = filter_status(scope) if status
      scope = scope.where(task_type: task_type) if task_type
      scope = scope.where(priority: priority.to_i) if priority
      scope = scope.where(id: TaskTag.where(tag_id: tag.id).select(:task_id)) if tag
      scope = filter_due(scope) if due
      scope
    end

    def tasks
      @tasks ||= begin
        rows = sorted(scope).includes(:tags, :subtasks, :parent_task, :recurrence).offset((page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
        @next_page = rows.size > PER_PAGE
        rows.first(PER_PAGE)
      end
    end

    def next_page?
      tasks
      @next_page
    end

    def previous_page?
      page > 1
    end

    def to_params(overrides = {})
      {
        q: q, status: status, task_type: task_type, priority: priority, tag_id: tag&.id, due: due,
        sort: (sort unless sort == "due"), archived: ("1" if archived?), subtasks: ("1" if subtasks?)
      }.merge(overrides).compact_blank
    end

    private
      attr_reader :user

      def pick(value, allowed)
        value = value.to_s
        value if allowed.include?(value)
      end

      def truthy?(value)
        ActiveModel::Type::Boolean.new.cast(value.presence) || false
      end

      def search(scope)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
        scope.where("LOWER(tasks.title) LIKE :pattern ESCAPE '\\' OR LOWER(COALESCE(tasks.description, '')) LIKE :pattern ESCAPE '\\'",
                    pattern: pattern)
      end

      def filter_status(scope)
        status == "open" ? scope.open : scope.where(status: status)
      end

      def filter_due(scope)
        case due
        when "today" then scope.where(due_at: Time.current.all_day)
        when "overdue" then scope.overdue
        when "week" then scope.where(due_at: Time.current.all_week)
        when "none" then scope.where(due_at: nil)
        end
      end

      def sorted(scope)
        case sort
        when "priority" then open_first(scope).order(priority: :desc).ordered
        when "recent" then scope.order(created_at: :desc, id: :desc)
        when "title" then scope.order(Arel.sql("LOWER(tasks.title)"), :id)
        else open_first(scope).ordered
        end
      end

      # Tasks still to do come before completed/cancelled ones.
      def open_first(scope)
        scope.order(Arel.sql("CASE WHEN tasks.status IN ('pending', 'in_progress') THEN 0 ELSE 1 END"))
      end
  end
end
