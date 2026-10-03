# Salary range and work mode, shared by JobListing and JobApplication so jobs can be
# filtered and compared. Amounts are gross euros; yearly salaries are compared as a
# monthly equivalent over 14 payments (the Portuguese norm).
module Compensation
  extend ActiveSupport::Concern

  WORK_MODES = { "remote" => "Remoto", "hybrid" => "Híbrido", "onsite" => "Presencial" }.freeze
  SALARY_PERIODS = { "month" => "por mês", "year" => "por ano" }.freeze
  PAYMENTS_PER_YEAR = 14

  included do
    validates :work_mode, inclusion: { in: WORK_MODES.keys }, allow_blank: true
    validates :salary_period, inclusion: { in: SALARY_PERIODS.keys }
    validates :salary_min, :salary_max, numericality: { only_integer: true, greater_than: 0, less_than: 10_000_000 },
                                        allow_nil: true
    validate :salary_range_in_order

    normalizes :work_mode, with: ->(mode) { mode.presence }

    scope :with_work_mode, ->(mode) { where(work_mode: mode) }
    # Jobs whose best salary (max, or min when there is no max) is at least +monthly+ euros/month.
    scope :paying_at_least, ->(monthly) {
      best = "COALESCE(#{table_name}.salary_max, #{table_name}.salary_min)"
      monthly_sql = "CASE WHEN #{table_name}.salary_period = 'year' THEN #{best} / #{PAYMENTS_PER_YEAR}.0 ELSE #{best} END"
      where("#{monthly_sql} >= ?", monthly.to_i)
    }
  end

  def work_mode_label
    WORK_MODES[work_mode]
  end

  def salary?
    salary_min.present? || salary_max.present?
  end

  # "1 200–1 500 € / mês", "a partir de 30 000 € / ano", "até 1 400 € / mês"
  def salary_label
    return nil unless salary?
    fmt = ->(n) { ActiveSupport::NumberHelper.number_to_delimited(n, delimiter: " ") }
    period = salary_period == "year" ? "ano" : "mês"
    amount =
      if salary_min && salary_max then salary_min == salary_max ? fmt.(salary_min) : "#{fmt.(salary_min)}–#{fmt.(salary_max)}"
      elsif salary_min then "a partir de #{fmt.(salary_min)}"
      else "até #{fmt.(salary_max)}"
      end
    "#{amount} € / #{period}"
  end

  # Monthly equivalent of the best salary, for sorting/comparing.
  def monthly_salary
    best = salary_max || salary_min
    return nil unless best
    salary_period == "year" ? (best.to_f / PAYMENTS_PER_YEAR).round : best
  end

  private
    def salary_range_in_order
      return unless salary_min && salary_max && salary_min > salary_max
      errors.add(:salary_max, "tem de ser maior ou igual ao salário mínimo")
    end
end
