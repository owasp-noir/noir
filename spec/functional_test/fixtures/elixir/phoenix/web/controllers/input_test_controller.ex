defmodule TestApp.Web.InputTestController do
  use TestApp.Web, :controller
  require Plug.Conn

  # Route: get "/input_test/params_in_signature/:user_id", TestApp.Web.InputTestController, :params_in_signature
  def params_in_signature(conn, %{"user_id" => user_id, "type" => type_param}) do
    # user_id (from path), type_param (from query)
    text(conn, "User ID: #{user_id}, Type: #{type_param}")
  end

  # Route: get "/input_test/headers_test", TestApp.Web.InputTestController, :headers_test
  def headers_test(conn, _params) do
    ua = Plug.Conn.get_req_header(conn, "user-agent")
    auth = conn.get_req_header("authorization") # Alternative call style
    x_custom = get_req_header(conn, "x-custom-header") # Direct call if imported
    text(conn, "Headers: #{ua}, #{auth}, #{x_custom}")
  end

  # Route: post "/input_test/cookies_test", TestApp.Web.InputTestController, :cookies_test
  def cookies_test(conn, _params) do
    # Ensure cookies are fetched if needed (though often automatic in Phoenix)
    # conn = Plug.Conn.fetch_cookies(conn) # Not strictly needed for req_cookies access if already parsed

    session_id = conn.req_cookies["session_id"]
    tracker_id = Map.get(conn.req_cookies, "tracker_id")
    text(conn, "Cookies: #{session_id}, #{tracker_id}")
  end

  # Route: get "/input_test/mixed_input/:item_id", TestApp.Web.InputTestController, :mixed_input
  def mixed_input(conn, %{"item_id" => item_id, "filter" => filter_param}) do
    # item_id (path), filter_param (query)
    custom_token = Plug.Conn.get_req_header(conn, "x-auth-token")
    pref_cookie = conn.req_cookies["user_preference"]

    text(conn, "Item: #{item_id}, Filter: #{filter_param}, Token: #{custom_token}, Pref: #{pref_cookie}")
  end

  # Route: get "/input_test/no_specific_inputs", TestApp.Web.InputTestController, :no_specific_inputs
  def no_specific_inputs(conn, _params) do
    text(conn, "No specific inputs here.")
  end
end
