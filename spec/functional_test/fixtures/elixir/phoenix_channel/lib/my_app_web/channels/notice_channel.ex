defmodule MyAppWeb.NoticeChannel do
  # Uses the generated `:channel` clause rather than `Phoenix.Channel`
  # directly. No handle_in clauses, so only the connection surface for its
  # mapped topic ("notice:lobby") is emitted.
  use MyAppWeb, :channel

  def join(_topic, _params, socket), do: {:ok, socket}
end
