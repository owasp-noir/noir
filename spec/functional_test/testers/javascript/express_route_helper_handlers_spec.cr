require "../../func_spec.cr"

# Routes registered through a forwarding helper (`setupApiRoute(router,
# 'put', '/:pid/vote', [...middlewares], controllers.write.posts.vote)`):
# the handler is the argument the helper's definition forwards as the last
# step (through its own `tryRoute(controller, onError)` wrapper), followed
# through `Controllers.write = require('./write')` barrels.
describe "Express route-helper handlers and params", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
    Noir::JSHandlerResolver.reset
  end

  it "resolves what the helper forwards" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_route_helper_handlers/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    find = ->(method : String, url : String) { endpoints.find! { |e| e.method == method && e.url == url } }
    handler_of = ->(method : String, url : String) do
      find.call(method, url).handler.try { |h| {File.basename(h.path || ""), h.line} }
    end
    params_of = ->(method : String, url : String) do
      find.call(method, url).params.map { |p| "#{p.name}:#{p.param_type}" }.sort!
    end

    # `Posts.vote = …` through controllers/index.js -> write/index.js -> posts.js.
    handler_of.call("PUT", "/api/v3/posts/:pid/vote").should eq({"posts.js", 11})
    params_of.call("PUT", "/api/v3/posts/:pid/vote").should eq(["delta:json", "pid:path"])
    # `Utilities.ping = {}; Utilities.ping.get = …`: a property path.
    handler_of.call("GET", "/api/v3/ping").should eq({"utilities.js", 6})
    # `Posts.pagination`, not `const pagination = require(...)`.
    handler_of.call("GET", "/api/v3/posts/:pid/pagination").should eq({"posts.js", 19})
    # `controllers` is a parameter routes/index.js hands the module in.
    handler_of.call("GET", "/feed/:tid.rss").should eq({"posts.js", 23})
    # ...and what the handler passes its request to reads `uid` (not the deleted `lang`).
    params_of.call("GET", "/feed/:tid.rss").should eq(["tid:path", "uid:query"])

    # `router.all('/api/v3/*', middleware.markApi)`: a pass-through serves nothing.
    handler_of.call("GET", "/api/v3/*").should be_nil

    # `/${name}/:pid` with `name` a parameter: the prefix really is a
    # variable there, so the route keeps its template and its handler.
    handler_of.call("GET", "/{name}/:pid").should eq({"posts.js", 7})
    # ...but a template two modules register with different handlers claims neither.
    handler_of.call("GET", "/{name}").should be_nil
  end
end
