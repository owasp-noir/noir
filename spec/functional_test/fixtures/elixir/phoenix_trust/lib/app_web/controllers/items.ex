defmodule AppWeb.Api.Items do
  use AppWeb, :controller
  use OpenApiSpex.ControllerSpecs

  operation(:index,
    summary: "List items",
    parameters: [
      limit: [in: :query, type: :integer],
      cursor: [
        in: :query,
        type: :string
      ]
    ]
  )

  def index(conn, _params) do
    json(conn, App.Items.list(conn.assigns.api_key, conn.query_params))
  end

  def update(
        %Plug.Conn{
          assigns: %{api_key: key}
        } = conn,
        %{"name" => name}
      ) do
    json(conn, App.Items.rename(key, name))
  end
end
