module Tasks
  # Keeps only the tag ids that belong to +user+; anything else (another user's tag,
  # garbage, the blank value sent by the form's hidden field) is silently dropped.
  #
  #   Tasks::OwnedTagIds.call(Current.user, [ "", "3", "999" ]) # => [ 3 ]
  class OwnedTagIds
    def self.call(user, ids)
      ids = Array(ids).map(&:to_s).grep(/\A\d+\z/)
      return [] if ids.empty?
      user.tags.where(id: ids).pluck(:id)
    end
  end
end
