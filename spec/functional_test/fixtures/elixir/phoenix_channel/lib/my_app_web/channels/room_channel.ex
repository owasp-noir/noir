defmodule MyAppWeb.RoomChannel do
  use Phoenix.Channel

  def join("room:" <> _room_id, _params, socket) do
    {:ok, socket}
  end

  # Client-invocable events.
  def handle_in("new_msg", %{"body" => body}, socket) do
    broadcast!(socket, "new_msg", %{body: body})
    {:noreply, socket}
  end

  def handle_in("typing", _payload, socket) do
    {:noreply, socket}
  end

  # A catch-all clause has no literal event name and is not emitted.
  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end
end
