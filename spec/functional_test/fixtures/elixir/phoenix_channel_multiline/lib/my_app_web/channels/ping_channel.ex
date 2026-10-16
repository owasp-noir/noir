defmodule MyAppWeb.PingChannel do
  use MyAppWeb, :channel

  def join("ping:" <> _id, _params, socket), do: {:ok, socket}

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{}}, socket}
  end
end
