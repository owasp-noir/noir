defmodule TestApp.Web.Router do
  use TestApp.Web, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    # Use a dummy plug for CSRF if you don't have one
    # plug TestApp.Web.Plugs.CSRFProtection
  end

  scope "/", TestApp.Web do
    pipe_through :browser

    get "/input_test/params_in_signature/:user_id", InputTestController, :params_in_signature
    get "/input_test/headers_test", InputTestController, :headers_test
    post "/input_test/cookies_test", InputTestController, :cookies_test
    get "/input_test/mixed_input/:item_id", InputTestController, :mixed_input
    get "/input_test/no_specific_inputs", InputTestController, :no_specific_inputs
  end
end
