class NotifiersController < ApplicationController
  before_action :authenticate_user!, :except => [:digest, :immediate]

  protect_from_forgery with: :null_session

# mysql> select n.id, n.event, n.user_id, n.notifiable_type, u.email, u.name, u.notifications, n.read from notifications n join users u on n.user_id = u.id where n.read = 1 and u.notifications = 2;

#  1 == Immediately after each event
#  2 == Daily summary of events
#  3 == No mail notifications at all

  def get_notifs_by_user(notification_type)
    notifs = Notification.joins("
        JOIN users ON
          notifications.user_id = users.id and
          notifications.created_at < (now() - interval 10 minute) and
          notifications.read = 0 and
          notifications.mailed = 0 and
          users.notifications = #{notification_type}
    ")
    .pluck(:id,:user_id,:name,:email,:notifications,:event)
    .map { |id, user_id, name, email, notifications, event| {id: id, user_id: user_id, name: name, email: email, notifications: notifications, event: event}}

    users = {}

    notifs.each do |n|
      if users.has_key?(n[:user_id])
        users[n[:user_id]].push(n)
      else
        users[n[:user_id]] = [ n ]
      end
    end

    return users

  end

  def send_notifs(notification_type, subject)
    users = get_notifs_by_user(notification_type)
    message = ''

    users.each do |user_id, events|
      user = events.first
      message = ''

      notifiee = {
        name: user[:name],
        subject: subject,
        email: user[:email],
        message: []
      }
      
      events.each do |event|
        notifiee[:message].push(event[:event])
        Notification.update(event[:id], mailed: true)
      end

      NotifierMailer.notify(notifiee).deliver_now
    end
  end

  def immediate
    head :unauthorized and return if !Socket.ip_address_list.select(&:ipv4?).map(&:ip_address).include?(request.remote_ip)
    subject = 'You have unread messages on SpaceDecentral.Net'
    send_notifs(1, subject)
  end

  def digest
    head :unauthorized and return if !Socket.ip_address_list.select(&:ipv4?).map(&:ip_address).include?(request.remote_ip)
    subject = 'You have unread messages on SpaceDecentral.Net (daily digest)'
    send_notifs(2, subject)
  end

end

