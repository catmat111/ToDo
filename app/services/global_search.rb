# Searches the user's own records at once (masthead search box).
#
#   GlobalSearch.new(Current.user, "acme").results
#   # => { tasks: [...], job_applications: [...], job_listings: [...], companies: [...], contacts: [...] }
class GlobalSearch
  LIMIT = 20
  # Columns searched per model (case-insensitive LIKE).
  FIELDS = {
    tasks: %w[title description],
    job_applications: %w[title company_name notes],
    job_listings: %w[title company_name location description],
    companies: %w[name location notes],
    contacts: %w[name email role notes]
  }.freeze

  attr_reader :query

  def initialize(user, query)
    @user = user
    @query = query.to_s.squish.first(100)
  end

  def searchable?
    query.length >= 2
  end

  def results
    return {} unless searchable?
    @results ||= FIELDS.to_h { |association, columns| [ association, search(association, columns) ] }
  end

  def total
    results.values.sum(&:size)
  end

  private
    def search(association, columns)
      scope = @user.public_send(association)
      table = scope.klass.table_name
      pattern = "%#{scope.klass.sanitize_sql_like(query.downcase)}%"
      condition = columns.map { |column| "LOWER(#{table}.#{column}) LIKE :q" }.join(" OR ")
      scope.where(condition, q: pattern).order(updated_at: :desc).limit(LIMIT).to_a
    end
end
