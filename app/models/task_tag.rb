class TaskTag < ApplicationRecord
  belongs_to :task
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :task_id }
  validate :same_owner

  private
    def same_owner
      return if task.nil? || tag.nil?
      errors.add(:tag, "tem de pertencer ao mesmo utilizador") if task.user_id != tag.user_id
    end
end
