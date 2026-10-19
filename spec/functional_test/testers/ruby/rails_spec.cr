require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/posts/1", "GET", [
    Param.new("X-API-KEY", "", "header"),
    # `params.fetch(:x)` and `params.dig(:top, ...)` read top-level keys too.
    Param.new("page", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PATCH", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/posts/1/search", "QUERY"),
  Endpoint.new("/search", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/filter", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/articles", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("alpha", "", "form"),
    Param.new("beta", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PUT", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PATCH", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/service-worker", "GET"),
  Endpoint.new("/manifest", "GET"),

  # devise_for :users under `scope :api`: `path_names: { sign_in: :login }`
  # renames the sessions path, and the model's `devise` line (no
  # :confirmable / :lockable) leaves out the confirmation and unlock routes.
  Endpoint.new("/api/users/login", "GET"),
  Endpoint.new("/api/users/login", "POST"),
  Endpoint.new("/api/users/sign_out", "DELETE"),
  Endpoint.new("/api/users/cancel", "GET"),
  Endpoint.new("/api/users/sign_up", "GET"),
  Endpoint.new("/api/users/edit", "GET"),
  Endpoint.new("/api/users", "PATCH"),
  Endpoint.new("/api/users", "PUT"),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/api/users", "POST"),
  Endpoint.new("/api/users/password/new", "GET"),
  Endpoint.new("/api/users/password", "POST"),
  Endpoint.new("/api/users/password/edit", "GET"),
  Endpoint.new("/api/users/password", "PATCH"),
  Endpoint.new("/api/users/password", "PUT"),

  # `resources :profiles, param: :username`: the member key is a path
  # segment, and the nested singular resource sees it as `profile_username`.
  Endpoint.new("/api/profiles/1", "GET", [
    Param.new("username", "", "path"),
  ]),
  Endpoint.new("/api/profiles/1/follow", "POST", [
    Param.new("profile_username", "", "path"),
  ]),
  Endpoint.new("/api/profiles/1/follow", "DELETE", [
    Param.new("profile_username", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/ruby/rails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reads fetch on bare params only, not on a *_params hash", tags: "functional" do
  show = tester.app.endpoints.find { |endpoint| endpoint.url == "/posts/1" && endpoint.method == "GET" }
  show.should_not be_nil
  show.not_nil!.params.map(&.name).should_not contain("theme")
end

it "does not carry show's params into create through `render :show`", tags: "functional" do
  create = tester.app.endpoints.find { |endpoint| endpoint.url == "/posts" && endpoint.method == "POST" }
  create.should_not be_nil
  create.not_nil!.params.map(&.name).should eq(["title", "context"])
end

it "points a Devise route at the `controllers:` override", tags: "functional" do
  login = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/users/login" && endpoint.method == "POST" }
  login.should_not be_nil
  handler = login.not_nil!.handler.not_nil!
  handler.name.should eq("sessions#create")
  handler.path.to_s.should end_with("app/controllers/sessions_controller.rb")
  handler.line.should eq(2)
end

it "emits no routes for Devise modules the model does not declare", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)
  urls.should_not contain("/api/users/sign_in")
  urls.any?(&.includes?("/confirmation")).should be_false
  urls.any?(&.includes?("/unlock")).should be_false
end
