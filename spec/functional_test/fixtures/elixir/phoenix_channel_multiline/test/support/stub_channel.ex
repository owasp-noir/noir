# Compiled only for MIX_ENV=test: a stub socket and channel that drive the
# app in tests, never served.
defmodule MyAppWeb.StubSocket do
  use Phoenix.Socket

  channel(
    "stub:*",
    MyAppWeb.StubChannel
  )
end

defmodule MyAppWeb.StubChannel do
  use Phoenix.Channel

  def handle_in("should_not_appear", _payload, socket), do: {:noreply, socket}
end
