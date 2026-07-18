defmodule MyAppWeb.UserSocket do
  use Phoenix.Socket

  # Topic → channel module mappings. These live in the socket module,
  # separate from the handle_in clauses in the channel modules.
  channel "room:*", MyAppWeb.RoomChannel
  channel "notice:lobby", MyAppWeb.NoticeChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
