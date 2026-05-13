module Testapp
  class Routes < Hanami::Routes
    get "/users", to: "users.index"
    post "/users", to: "users.create"
    get "/users/:id", to: "users.show"
    delete "/users/:id", to: "users.destroy"
    get "/ready", to: "health.ready"
    get "/missing", to: "missing.index"
  end
end
