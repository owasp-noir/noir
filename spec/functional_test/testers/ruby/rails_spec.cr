require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/posts/:id", "GET", [
    Param.new("X-API-KEY", "", "header"),
    # `params.fetch(:x)` reads a top-level key; `params.dig(:filter, :status)`
    # reads the leaf, as `params[:filter][:status]` does.
    Param.new("page", "", "query"),
    Param.new("status", "", "query"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  # `before_action :check_header, only: %i[ edit update ]` reads X-API-KEY.
  Endpoint.new("/posts/:id", "PUT", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/:id", "PATCH", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/:id", "DELETE"),
  # `resources` also routes the `new` / `edit` form pages the controller defines.
  Endpoint.new("/posts/new", "GET"),
  Endpoint.new("/posts/:id/edit", "GET", [
    Param.new("X-API-KEY", "", "header"),
  ]),
  Endpoint.new("/posts/:id/search", "QUERY"),
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
    Param.new("gamma", "", "form"),
    Param.new("flag", "", "form"),
    Param.new("ref", "", "form"),
    Param.new("pinned", "", "form"),
  ]),
  Endpoint.new("/articles/:id", "PUT", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/articles/:id", "PATCH", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/service-worker", "GET"),
  Endpoint.new("/manifest", "GET"),

  # devise_for :users under `scope :api`: `path_names: { sign_in: :login }`
  # renames the sessions path, `config.sign_out_via = :get` in
  # `config/initializers/devise.rb` switches sign_out to GET, and the model's
  # `devise` line (no :confirmable / :lockable, with :omniauthable) leaves out
  # confirmation/unlock while adding the OmniAuth routes.
  Endpoint.new("/api/users/login", "GET"),
  Endpoint.new("/api/users/login", "POST", [
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
  ]),
  Endpoint.new("/api/users/sign_out", "GET"),
  Endpoint.new("/api/users/cancel", "GET"),
  Endpoint.new("/api/users/sign_up", "GET"),
  Endpoint.new("/api/users/edit", "GET"),
  Endpoint.new("/api/users", "PATCH", [
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
    Param.new("password_confirmation", "", "json"),
    Param.new("current_password", "", "json"),
  ]),
  Endpoint.new("/api/users", "PUT", [
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
    Param.new("password_confirmation", "", "json"),
    Param.new("current_password", "", "json"),
  ]),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/api/users", "POST", [
    Param.new("email", "", "json"),
    Param.new("password", "", "json"),
    Param.new("password_confirmation", "", "json"),
  ]),
  Endpoint.new("/api/users/password/new", "GET"),
  Endpoint.new("/api/users/password", "POST", [
    Param.new("email", "", "json"),
  ]),
  Endpoint.new("/api/users/password/edit", "GET"),
  Endpoint.new("/api/users/password", "PATCH", [
    Param.new("reset_password_token", "", "json"),
    Param.new("password", "", "json"),
    Param.new("password_confirmation", "", "json"),
  ]),
  Endpoint.new("/api/users/password", "PUT", [
    Param.new("reset_password_token", "", "json"),
    Param.new("password", "", "json"),
    Param.new("password_confirmation", "", "json"),
  ]),
  Endpoint.new("/api/users/auth/:provider", "GET"),
  Endpoint.new("/api/users/auth/:provider", "POST"),
  Endpoint.new("/api/users/auth/:provider/callback", "GET"),
  Endpoint.new("/api/users/auth/:provider/callback", "POST"),

  # `resources :profiles, param: :username`: the member key is a path
  # segment, and the nested singular resource sees it as `profile_username`.
  Endpoint.new("/api/profiles/:username", "GET", [
    Param.new("username", "", "path"),
  ]),
  Endpoint.new("/api/profiles/:profile_username/follow", "POST", [
    Param.new("profile_username", "", "path"),
  ]),
  Endpoint.new("/api/profiles/:profile_username/follow", "DELETE", [
    Param.new("profile_username", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/ruby/rails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reads subscript and fetch on bare params only, while attaching Devise sign_in_params", tags: "functional" do
  show = tester.app.endpoints.find { |endpoint| endpoint.url == "/posts/:id" && endpoint.method == "GET" }
  show.should_not be_nil
  show.not_nil!.params.map(&.name).should_not contain("theme")

  login = tester.app.endpoints.find { |endpoint| endpoint.url == "/api/users/login" && endpoint.method == "POST" }
  login.should_not be_nil
  login.not_nil!.params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(["email:json", "password:json"])
  login.not_nil!.params.map(&.name).should_not contain("remember_token")
end

it "reads nested and scalar-require params by the key the form sends, never the wrapper", tags: "functional" do
  create = tester.app.endpoints.find { |endpoint| endpoint.url == "/articles" && endpoint.method == "POST" }
  create.should_not be_nil
  names = create.not_nil!.params.map(&.name)
  names.should_not contain("article")
  names.should_not contain("thing")
  names.should_not contain("other")
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
  tester.app.endpoints.any? { |e| e.url == "/api/users/sign_out" && e.method == "DELETE" }.should be_false
end
