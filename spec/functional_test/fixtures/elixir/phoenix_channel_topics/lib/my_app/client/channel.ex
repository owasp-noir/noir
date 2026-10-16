defmodule MyApp.Client.Channel do
  use MyAppWeb, :channel

  def join("client", _params, socket), do: {:ok, socket}

  def handle_in("create_flow", _payload, socket), do: {:noreply, socket}

  # Delegates every other event to a helper module that no socket maps to a
  # topic.
  def handle_in(message, payload, socket) do
    MyApp.Client.Channel.Shared.handle_in(message, payload, socket)
  end
end
