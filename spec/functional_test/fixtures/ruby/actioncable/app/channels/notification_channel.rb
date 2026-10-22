class NotificationChannel < ApplicationCable::Channel
  # A channel with no client-invocable actions (only lifecycle callbacks).
  # Its connection surface is still emitted as a bare endpoint.
  def subscribed
    stream_for current_user
  end

  def unsubscribed
  end
end
