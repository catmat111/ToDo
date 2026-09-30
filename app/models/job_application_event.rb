class JobApplicationEvent < ApplicationRecord
  EVENT_TYPES = %w[saved applied interview offer rejected withdrawn follow_up note].freeze
  EVENT_LABELS = JobApplication::STATUS_LABELS.merge("follow_up" => "Follow-up", "note" => "Nota").freeze
  # Types a user typically adds by hand, shown first in the "Adicionar evento" select.
  MANUAL_TYPES = %w[note follow_up].freeze

  belongs_to :job_application, touch: true

  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :occurred_at, presence: true
  validates :notes, length: { maximum: 5_000 }
  validate :occurred_at_not_absurd

  scope :newest_first, -> { reorder(occurred_at: :desc, id: :desc) }

  def self.label_for(event_type)
    EVENT_LABELS.fetch(event_type.to_s, event_type.to_s.humanize)
  end

  def label
    self.class.label_for(event_type)
  end

  # Events that mirror a status of the application (as opposed to notes / follow-ups).
  def status_event?
    JobApplication::STATUSES.include?(event_type)
  end

  private
    def occurred_at_not_absurd
      return if occurred_at.blank?
      if occurred_at < Time.zone.local(1990) || occurred_at > 5.years.from_now
        errors.add(:occurred_at, "não é uma data válida para o histórico")
      end
    end
end
