defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  # `mix format` breaks a declaration that does not fit in 98 columns across
  # several lines.
  channel(
    "organization_notifications:*",
    MyAppWeb.Organizations.NotificationPreferencesChannel
  )

  channel "ping:*", MyAppWeb.PingChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
