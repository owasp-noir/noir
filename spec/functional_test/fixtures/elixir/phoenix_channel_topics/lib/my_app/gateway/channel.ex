defmodule MyApp.Gateway.Channel do
  use MyAppWeb, :channel

  def join("gateway", _params, socket), do: {:ok, socket}

  def handle_in("flow_authorized", _payload, socket), do: {:noreply, socket}
end
