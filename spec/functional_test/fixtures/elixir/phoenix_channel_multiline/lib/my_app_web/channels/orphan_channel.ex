defmodule MyAppWeb.OrphanChannel do
  use MyAppWeb, :channel

  # No socket maps a topic to this module, so it can never be joined.
  def handle_in("orphan_event", _payload, socket), do: {:noreply, socket}
end
