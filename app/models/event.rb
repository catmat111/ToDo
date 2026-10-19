# Something on the calendar that happens at a time (meeting, dinner, class) — unlike a
# Task, it isn't done or pending. All-day events span whole days.
class Event < ApplicationRecord
  belongs_to :user

  normalizes :title, with: ->(t) { t.squish }
  normalizes :location, with: ->(l) { l.squish.presence }

  validates :title, presence: true, length: { maximum: 200 }
  validates :starts_at, presence: { message: "tem de ser indicado" }
  validates :location, length: { maximum: 200 }
  validates :notes, length: { maximum: 5000 }
  validate :ends_after_start

  before_validation :spread_all_day

  scope :chronological, -> { order(:starts_at, :id) }
  # Events touching [from, to]: starting inside it, or started before and still going.
  scope :overlapping, ->(range) {
    where(starts_at: range).or(where(starts_at: ...range.begin, ends_at: range.begin..))
  }

  def first_day
    starts_at.in_time_zone.to_date
  end

  def last_day
    (ends_at || starts_at).in_time_zone.to_date
  end

  def on?(date)
    date.between?(first_day, last_day)
  end

  private
    def ends_after_start
      return if starts_at.blank? || ends_at.blank?
      errors.add(:ends_at, "tem de ser depois do início") if ends_at < starts_at
    end

    # An all-day event covers its days from midnight to midnight.
    def spread_all_day
      return unless all_day? && starts_at
      self.starts_at = starts_at.in_time_zone.beginning_of_day
      self.ends_at = (ends_at || starts_at).in_time_zone.end_of_day.change(usec: 0)
    end
end
