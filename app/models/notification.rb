class Notification < ApplicationRecord
  TYPES = %w[reminder task_due application calendar share system].freeze
  TYPE_LABELS = {
    "reminder" => "Lembrete", "task_due" => "Prazo", "application" => "Candidatura",
    "calendar" => "Calendário", "share" => "Partilha", "system" => "Sistema"
  }.freeze
  FILTERS = %w[all unread].freeze

  belongs_to :user
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :notification_type, inclusion: { in: TYPES }
  validates :title, presence: true, length: { maximum: 255 }

  # Live updates (Turbo Streams over Action Cable) on the user's own stream,
  # subscribed in the layout with turbo_stream_from(Current.user, :notifications).
  after_create_commit :broadcast_created
  after_update_commit :broadcast_badge, if: :saved_change_to_read_at?

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

  private
    def stream
      [ user, :notifications ]
    end

    # New row on the notifications page (if open), a pop-up on any page, and the sidebar count.
    # A failed broadcast must never undo the notification itself.
    def broadcast_created
      broadcast_prepend_to stream, target: "notifications", partial: "notifications/notification",
                                   locals: { notification: self }
      broadcast_append_to stream, target: "toasts", partial: "notifications/toast", locals: { notification: self }
      broadcast_badge
    rescue StandardError => e
      Rails.logger.warn("[notifications] live update failed for notification #{id}: #{e.class}")
    end

    def broadcast_badge
      broadcast_replace_to stream, target: "nav_notifications_badge", partial: "notifications/badge",
                                   locals: { count: user.notifications.unread.count }
    rescue StandardError => e
      Rails.logger.warn("[notifications] badge update failed for user #{user_id}: #{e.class}")
    end
end
