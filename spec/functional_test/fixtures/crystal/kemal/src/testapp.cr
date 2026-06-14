require "kemal"

get "/" do
  env.request.headers["x-api-key"].as(String)
  "Hello World!"
end

# get "/commented" do
#   env.params.query["ghost"]
# end

get("/paren") do |env|
  env.params.query["kind"]
  "parenthesized"
end

post "/query" do
  env.request.cookies["my_auth"].as(String)
  env.params.body["query"].as(String)
end

get "/token" do
  env.params.body["client_id"].as(String)
  env.params.body["redirect_url"].as(String)
  env.params.body["grant_type"].as(String)
end

ws "/socket" do |socket|
  socket.send "Hello from Kemal!"
end

api = Kemal::Router.new
api.namespace "/users" do
  get "/" do |env|
    env.params.query["page"]
    "user list"
  end
  get "/:id" do |_|
    "user detail"
  end
end
mount "/api/v1", api

public_folder "custom_public"

# A documentation string that embeds example routing inside a heredoc.
# Heredoc bodies are string DATA, not executable routing DSL, so none of
# the verbs below may surface as endpoints. The terminator must also stop
# the masking so the real route declared afterwards is still detected.
USAGE = <<-MD
  ## Routing example

      get "/ghost-in-heredoc" do
        env.params.query["leak"]
      end

      post "/ghost-in-heredoc/submit" do
      end
  MD

get "/after-heredoc" do
  "still routed"
end

Kemal.run
