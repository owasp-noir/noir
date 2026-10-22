defmodule Plug.Router do
  @moduledoc ~S"""
  A DSL to define a routing algorithm that works with Plug.

  It provides a set of macros to generate routes. For example:

      defmodule AppRouter do
        use Plug.Router

        plug :match
        plug :dispatch

        get "/hello" do
          send_resp(conn, 200, "world")
        end

        match _ do
          send_resp(conn, 404, "oops")
        end
      end

  Each route receives a `conn` variable containing a `Plug.Conn`
  struct and it needs to return a connection, as per the Plug spec.
  """

  defmacro get(path, options, contents \\ []) do
    compile(:get, path, options, contents)
  end
end
