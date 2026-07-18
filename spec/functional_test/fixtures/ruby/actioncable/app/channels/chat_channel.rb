class ChatChannel < ApplicationCable::Channel
  def subscribed
    stream_from "chat_#{params[:room]}"
  end

  def unsubscribed
    stop_all_streams
  end

  # Client-invocable actions (called via perform("speak", ...)).
  def speak(data)
    ActionCable.server.broadcast("chat", message: data["message"])
  end

  def typing(data)
    ActionCable.server.broadcast("chat", typing: true)
  end

  private

  # Private helpers are not client-invocable actions.
  def sanitize(text)
    text.strip
  end
end
