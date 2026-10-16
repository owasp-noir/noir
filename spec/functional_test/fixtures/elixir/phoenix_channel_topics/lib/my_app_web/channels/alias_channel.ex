defmodule MyApp.Channels.AliasChannel do
  use Phoenix.Channel

  def join("alias:" <> _id, _params, socket), do: {:ok, socket}

  def handle_in("hello", _payload, socket), do: {:noreply, socket}
end
