class Notification < ApplicationRecord
  TYPES = %w[reminder task_due application calendar system].freeze
  TYPE_LABELS = {
    "reminder" => "Lembrete", "task_due" => "Prazo", "application" => "Candidatura",
    "calendar" => "Calendário", "system" => "Sistema"
  }.freeze
  FILTERS = %w[all unread].freeze

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :notification_type, inclusion: { in: TYPES }
  validates :title, presence: true, length: { maximum: 255 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :of_type, ->(type) { where(notification_type: type) }
  scope :for_filter, ->(filter) { filter.to_s == "unread" ? unread : all }

  def self.mark_all_read!(now = Time.current)
    unread.update_all(read_at: now, updated_at: now)
  end

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  def type_label
    TYPE_LABELS.fetch(notification_type, notification_type.to_s.humanize)
  end
end
