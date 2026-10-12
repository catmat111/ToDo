# "N respostas novas ... para rever" notifications were created without a target;
# point them at the user's mailbox connection so they open the replies page.
class LinkReplyNotificationsToMailbox < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE notifications
      SET notifiable_type = 'MailboxConnection',
          notifiable_id = (SELECT id FROM mailbox_connections WHERE mailbox_connections.user_id = notifications.user_id)
      WHERE notifiable_id IS NULL
        AND notification_type = 'application'
        AND title LIKE '%para rever'
        AND EXISTS (SELECT 1 FROM mailbox_connections WHERE mailbox_connections.user_id = notifications.user_id)
    SQL
  end

  def down
  end
end
