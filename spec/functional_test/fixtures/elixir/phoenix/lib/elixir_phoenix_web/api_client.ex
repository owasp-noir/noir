defmodule ElixirPhoenixWeb.ApiClient do
  # HTTP-CLIENT wrapper — these `post`/`get` calls hit a REMOTE API, they
  # are NOT Phoenix routes. The 2nd arg is either a lowercase variable or a
  # `Module.fn(...)` call (not a controller module), so none may surface as
  # endpoints. Regression guard for the optional-action route matcher.
  def create_session(params, team) do
    post("/api/v1/org/secrets", params, team)
    post("com.atproto.repo.createRecord", Jason.encode!(params), team)
    get("/remote/status", client_opts, team)
  end
end
