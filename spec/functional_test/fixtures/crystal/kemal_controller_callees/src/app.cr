require "kemal"
require "./routes/misc"
require "./routes/api/items"

# invidious-style routing: every route names a controller module and an
# action method rather than carrying an inline `do … end` block. The
# handler bodies live in other files, and a chunk of them reference the
# controller through a compile-time macro variable.
module App::Routing
  extend self

  def register_all
    get "/", Routes::Misc, :home
    post "/users", Routes::Misc, :create_user

    register_api_routes
  end

  def register_api_routes
    {% begin %}
      {{ namespace = Routes::API }}

      get "/api/items/:id", {{ namespace }}::Items, :show
    {% end %}
  end
end

App::Routing.register_all
Kemal.run
