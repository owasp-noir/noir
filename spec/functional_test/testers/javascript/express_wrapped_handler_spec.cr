require "../../func_spec.cr"

# `router.get('/x', asyncHandler(async (req, res) => {…}), respond)`: the
# handler is the closure the transparent wrapper hands the request to, not
# the wrapper call and not the shared `respond` renderer after it; and a
# handler that refuses a caller without a user at its top is guarded.
describe "Express wrapped handlers and in-handler caller checks", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves the served handler and judges in-handler checks by their code" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_wrapped_handler/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    handler_of = ->(method : String, url : String) do
      ep = endpoints.find! { |e| e.method == method && e.url == url }
      ep.handler.try { |h| {h.name, h.line} }
    end
    guards_of = ->(method : String, url : String) do
      endpoints.find! { |e| e.method == method && e.url == url }.ai_context.try(&.guards.map(&.source)) || [] of String
    end

    # Named step before the shared renderer: its own definition.
    handler_of.call("GET", "/items").should eq({"readHandler", 10})
    # Inline closures inside the wrapper (trailing comma included).
    handler_of.call("GET", "/random").should eq({"closure", 19})
    handler_of.call("POST", "/sort").should eq({"closure", 26})
    # A step that reads res.locals but ends only this route is the handler.
    handler_of.call("GET", "/me").should eq({"showMe", 38})
    # `allow(check)` consults its argument; it is not a transparent wrapper.
    handler_of.call("POST", "/checked").should be_nil

    guards_of.call("PATCH", "/me/page").should eq(["express_auth"])
    guards_of.call("GET", "/things/:id/mine").should eq(["express_auth"])
    guards_of.call("GET", "/things/:id").should be_empty
    guards_of.call("GET", "/cached").should be_empty
    guards_of.call("GET", "/staff").should be_empty
    guards_of.call("GET", "/random").should be_empty

    # src/review.ts: wrapper shapes (generic, multi-line), guard wrappers,
    # identity vs. request data, renderer link, multi-line mounts.
    handler_of.call("GET", "/r/admin").should eq({"list", 13})
    guards_of.call("GET", "/r/admin").should eq(["express_auth"])
    handler_of.call("GET", "/r/authed").should eq({"list", 13})
    guards_of.call("GET", "/r/authed").should eq(["express_auth"])
    guards_of.call("GET", "/r/schema").should eq(["express_auth"])
    guards_of.call("GET", "/r/items/:collection").should be_empty
    guards_of.call("GET", "/r/shared").should be_empty
    {"/r/users/:userId/posts", "/r/leak", "/r/users/:userId/things", "/r/stats"}.each do |url|
      guards_of.call("GET", url).should be_empty
    end
    guards_of.call("POST", "/r/requests/:id/accept").should be_empty
    handler_of.call("GET", "/r/me").should eq({"showProfile", 57})
    guards_of.call("GET", "/r/private/a").should eq(["express_auth"])
    guards_of.call("GET", "/r/open").should be_empty
  end
end
