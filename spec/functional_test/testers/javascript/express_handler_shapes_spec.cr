require "../../func_spec.cr"

# Shapes where reading a handler or a guard off its definition has to look
# at what the definition actually does: which argument a wrapper calls,
# which definition a module exports, which conditions a refusal sits under.
describe "Express handler and guard shapes", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
    Noir::JSHandlerResolver.reset
  end

  it "reads handlers, guards and params by definition" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_handler_shapes/")])
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
    guards_of = ->(method : String, url : String) do
      find.call(method, url).ai_context.try(&.guards.map(&.description.to_s)) || [] of String
    end
    params_of = ->(method : String, url : String) do
      find.call(method, url).params.map { |p| "#{p.name}:#{p.param_type}" }.sort!
    end

    # `wrap2(logErr, real)` calls `fn`, its second parameter, with the request.
    handler_of.call("GET", "/wrap").should eq({"app.js", 15})
    # `secured(ensureAuthenticated, router, 'get', '/secret', real)`.
    guards_of.call("GET", "/secret").size.should eq(1)
    # A setting decides it: the guard says so.
    guards_of.call("GET", "/maybe").first.should contain("a setting can")
    # `if (req.method !== 'GET')` inside the guest branch: writes only.
    guards_of.call("GET", "/reads").should be_empty
    guards_of.call("POST", "/reads").size.should eq(1)
    # `open.splice(0, 1)` empties the array before the route sees it.
    guards_of.call("GET", "/opened").should be_empty

    # `req.body.sort = 'asc'` and `fromRemote({ session }, …)` read nothing.
    params_of.call("GET", "/defaults").should eq(["page:query"])
    # `reply(req)` answers through the request: `show` is still the handler.
    handler_of.call("GET", "/items/:id").should eq({"app.js", 60})

    # `Posts.list = …`, not the `const list` inside `Posts.summary`.
    handler_of.call("GET", "/posts").should eq({"posts.js", 8})
    # `{ ...require('./a'), ...require('./b') }`: the later spread wins.
    handler_of.call("GET", "/spread").should eq({"b.js", 1})
    # `exports.thing` assigned twice: the last one is exported.
    handler_of.call("GET", "/over").should eq({"over.js", 2})
    # `controllers` is rebound by `inner`'s own parameter: neither is claimed.
    handler_of.call("GET", "/shadow/outer").should be_nil
    handler_of.call("GET", "/shadow/inner").should be_nil
    handler_of.call("POST", "/install").should eq({"app.js", 76})
  end
end
