defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  # `mix format` writes channel declarations with parentheses.
  channel("conversation:*", MyAppWeb.ConversationChannel)
  # Three modules share the short name `Channel`: each topic must still
  # reach its own module.
  channel "client", MyApp.Client.Channel
  channel "gateway", MyApp.Gateway.Channel
  # Declared through a partial alias (`alias MyApp.Channels`).
  channel("alias:*", Channels.AliasChannel)

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
