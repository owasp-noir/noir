# Compiled only for MIX_ENV=test (`elixirc_paths(:test)`): a stub of an
# upstream API that the test suite talks to. Never served by the app.
defmodule TestSupport.StubRouter do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/should-not-appear-test-support" do
    send_resp(conn, 200, "")
  end
end
