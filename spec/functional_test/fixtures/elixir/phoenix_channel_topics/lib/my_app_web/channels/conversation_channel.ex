defmodule MyAppWeb.ConversationChannel do
  use MyAppWeb, :channel

  def join("conversation:" <> _id, _params, socket), do: {:ok, socket}

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{}}, socket}
  end
end
