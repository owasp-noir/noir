defmodule MyAppWeb.Organizations.NotificationPreferencesChannel do
  use MyAppWeb, :channel

  def join("organization_notifications:" <> _id, _params, socket), do: {:ok, socket}

  def handle_in("update_preferences", _payload, socket) do
    {:reply, {:ok, %{}}, socket}
  end
end
