defmodule MyApp.Client.Channel.Shared do
  use MyAppWeb, :channel

  def handle_in("resolve_device", _payload, socket), do: {:noreply, socket}
end
