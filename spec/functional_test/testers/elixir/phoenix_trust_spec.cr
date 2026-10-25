require "../../func_spec.cr"

# What an agent tracing a Phoenix route needs from it:
#   * handler: the controller action's first clause, also for a controller
#     outside a `*_controller.ex` file that the route names by full module
#     and for a head that pattern-matches `%Plug.Conn{...} = conn`;
#   * auth: a plug is a guard by its definition (reads the caller and can
#     answer 401/403 or redirect to log in), not its name: a pipeline named
#     `:auth` that only loads the user is not one, a module plug named in
#     `pipe_through` is judged too, a controller plug obeys its `when action
#     in` list (module attributes resolved), and a plug that redirects
#     signed-in users away is not one; an action that refuses anonymous
#     callers itself guards; the route's own action name (`:authenticate`)
#     is not a guard;
#   * params: a private helper the action passes `conn` to, and OpenApiSpex
#     `operation(:action, parameters: [...])` declarations.
describe "Phoenix handler / plug-definition auth / helper params", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/elixir/phoenix_trust/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves what serves each route and who may call it" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
    find = ->(method : String, url : String) { endpoints.find! { |ep| ep.method == method && ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }
    params = ->(ep : Endpoint) { ep.params.map { |p| "#{p.name}:#{p.param_type}" }.sort! }

    home = find.call("GET", "/")
    handler = home.handler.should_not be_nil
    handler.name.should eq("AppWeb.PageController.home")
    handler.path.to_s.should end_with("lib/app_web/controllers/page_controller.ex")
    handler.line.should eq(13)
    guards.call(home).should be_empty

    share = find.call("POST", "/share/:slug/authenticate")
    guards.call(share).should be_empty
    params.call(share).should eq(["password:form", "return_to:query", "slug:path"])

    guards.call(find.call("GET", "/edit")).should eq(["Phoenix AppWeb.RequireAccount plug"])
    guards.call(find.call("GET", "/me")).should eq(["Phoenix me action check"])
    guards.call(find.call("GET", "/guest")).should be_empty
    guards.call(find.call("DELETE", "/settings/keys/:id")).should eq(["Phoenix :account pipeline"])

    index = find.call("GET", "/api/v1/items")
    index.handler.try(&.path).to_s.should end_with("lib/app_web/controllers/items.ex")
    index.handler.try(&.line).should eq(16)
    guards.call(index).should eq(["Phoenix AppWeb.ApiAuth plug"])
    params.call(index).should eq(["cursor:query", "limit:query"])

    update = find.call("PATCH", "/api/v1/items/:id")
    update.handler.try(&.line).should eq(20)
    params.call(update).should eq(["id:path", "name:form"])
  end
end
