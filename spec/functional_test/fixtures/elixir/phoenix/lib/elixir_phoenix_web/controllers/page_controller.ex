defmodule ElixirPhoenixWeb.PageController do
  use ElixirPhoenixWeb, :controller

  def home(conn, _params) do
    # Query parameters
    search_query = conn.query_params["q"]
    page_number = conn.params["page"]
    limit = conn.params["limit"]
    
    render(conn, :home)
  end
end
