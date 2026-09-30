class TaskRecurrence < ApplicationRecord
  FREQUENCIES = %w[daily weekly monthly yearly].freeze
  FREQUENCY_LABELS = { "daily" => "Diária", "weekly" => "Semanal", "monthly" => "Mensal", "yearly" => "Anual" }.freeze

  belongs_to :task

  enum :frequency, FREQUENCIES.index_by(&:itself), validate: true

  validates :interval, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }

  def self.frequency_label(frequency)
    FREQUENCY_LABELS.fetch(frequency.to_s, frequency.to_s.humanize)
  end

  # +time+ moved forward by one step of this rule, ignoring ends_at.
  def advance(time)
    return nil if time.nil?
    case frequency
    when "daily" then time + interval.days
    when "weekly" then time + interval.weeks
    when "monthly" then time + interval.months
    when "yearly" then time + interval.years
    end
  end

  # Next occurrence of +time+ according to this rule, or nil when the rule has ended.
  def next_time(time)
    candidate = advance(time)
    return nil if candidate.nil?
    ends_at.present? && candidate > ends_at ? nil : candidate
  end
end
