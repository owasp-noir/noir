defmodule TestSupport.StubPhoenixRouter do
  use Phoenix.Router

  scope "/", TestSupport do
    get "/should-not-appear-test-phoenix", StubController, :index
  end
end
