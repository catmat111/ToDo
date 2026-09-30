class AuditLogsController < ApplicationController
  LIMIT = 200

  # Filter tabs: key => action prefixes.
  SCOPES = {
    "conta" => %w[user.],
    "tarefas" => %w[task.],
    "emprego" => %w[job_application. job_search. job_listing.],
    "calendario" => %w[calendar.]
  }.freeze

  # Resource types that can be linked, and the Current.user association that owns them.
  RESOURCE_ASSOCIATIONS = {
    "Task" => :tasks,
    "Tag" => :tags,
    "JobApplication" => :job_applications,
    "JobSearch" => :job_searches,
    "JobListing" => :job_listings,
    "CalendarConnection" => :calendar_connections
  }.freeze

  def index
    @scope = params[:scope].presence_in(SCOPES.keys)
    @audit_logs = filtered_logs.recent.limit(LIMIT).to_a
    @resources = load_resources(@audit_logs)
  end

  private
    def filtered_logs
      logs = Current.user.audit_logs
      return logs unless @scope

      conditions = SCOPES.fetch(@scope).map do |prefix|
        AuditLog.arel_table[:action].matches("#{AuditLog.sanitize_sql_like(prefix)}%", "\\")
      end
      logs.where(conditions.reduce(:or))
    end

    # { ["Task", 12] => #<Task> } — only records that still exist and belong to the user,
    # loaded with one query per type so deleted resources simply render without a link.
    def load_resources(logs)
      logs.select { |log| log.resource_id && RESOURCE_ASSOCIATIONS.key?(log.resource_type) }
          .group_by(&:resource_type)
          .each_with_object({}) do |(type, entries), found|
            Current.user.public_send(RESOURCE_ASSOCIATIONS.fetch(type))
                        .where(id: entries.map(&:resource_id).uniq)
                        .each { |record| found[[ type, record.id ]] = record }
          end
    end
end
