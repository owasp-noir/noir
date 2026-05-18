# Regression guard: ExUnit `*_test.exs` files register routes only to
# exercise the framework; the routes never serve real traffic. None of
# the URLs below should appear in the fixture's expected-endpoints list.
defmodule ElixirPlug.RouterTest do
  use ExUnit.Case
  use Plug.Test

  defmodule TestRouter do
    use Plug.Router

    plug :match
    plug :dispatch

    get "/should-not-appear-test-get", do: send_resp(conn, 200, "")
    post "/should-not-appear-test-post", do: send_resp(conn, 200, "")
  end

  test "noop" do
    assert true
  end
end
