require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# net/http has no `.Use`: GoAuthTagger reads what wraps a ServeMux route's
# handler or mux in the registering function, each wrapper judged by its
# definition (see `net_http_guards`).
describe "GoAuthTagger net/http wrappers" do
  base = File.expand_path("../../../functional_test/fixtures/go/http_wrapped", __DIR__)

  guards = ->(file : String, line : Int32, url : String, method : String) do
    CodeLocator.instance.clear_all
    Dir.glob("#{base}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
    options = create_test_options
    options["base"] = YAML::Any.new(base)
    details = Details.new(PathInfo.new("#{base}/#{file}", line))
    details.technology = "go_http"
    endpoint = Endpoint.new(url, method, [] of Param, details)
    GoAuthTagger.new(options).perform([endpoint]).first.tags.map(&.description)
  end

  it "reads the wrappers of the mux, through helpers of other packages" do
    # `return mw.withCORS(mw.requireKey(mux))`: requireKey refuses through
    # `response.Unauthorized`, withCORS only answers a preflight.
    guards.call("api/api.go", 12, "/v1/items", "POST").should eq(["Protected by Go middleware mw.requireKey (verified from its body: refuses anonymous callers)"])
  end

  it "reads a local closure that wraps the handler, and the methods it reaches" do
    guards.call("reader/reader.go", 16, "/reader/edit", "POST").should eq(["Protected by Go middleware auth.validate (verified from its body: refuses anonymous callers)"])
    guards.call("reader/reader.go", 15, "/reader/login", "POST").should be_empty
  end

  it "counts a middleware that stops the request when the credential it reads is empty" do
    guards.call("server/routes.go", 19, "/fever/", "GET").should eq(["Protected by Go middleware fever.Middleware (verified from its body: refuses anonymous callers)"])
  end

  it "reads a path predicate in the refusal's condition for the route" do
    guards.call("ui/ui.go", 14, "/items/{id}/remove", "POST").should eq(["Protected by Go middleware session.handle (verified from its body: refuses anonymous callers)"])
    guards.call("ui/ui.go", 13, "/login", "GET").should be_empty
    guards.call("ui/ui.go", 15, "/share/{code}", "GET").should be_empty
    guards.call("ui/ui.go", 16, "/static/{file}", "GET").should be_empty
    # `GET /{$}` is `/` only, which the predicate lists as public.
    guards.call("ui/ui.go", 17, "/", "GET").should be_empty
  end

  it "says when a setting lifts the guard" do
    # `if token == "" { return next }` in the factory.
    guards.call("jobs/jobs.go", 11, "/jobs/run", "POST").should eq(["Protected by Go middleware auth (verified from its body: refuses anonymous callers; a setting can lift it: it hands the request on unchecked when `token == \"\"`)"])
  end

  it "leaves routes no refusing wrapper reaches open" do
    guards.call("server/routes.go", 30, "/liveness", "GET").should be_empty
    guards.call("server/routes.go", 17, "/healthcheck", "GET").should be_empty
  end

  # Lookalikes that must stay open (see the fixture's comments).
  cases = File.expand_path("../../../functional_test/fixtures/go/http_guard_cases", __DIR__)
  case_guards = ->(line : Int32, url : String, method : String) do
    CodeLocator.instance.clear_all
    Dir.glob("#{cases}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
    options = create_test_options
    options["base"] = YAML::Any.new(cases)
    details = Details.new(PathInfo.new("#{cases}/main.go", line))
    details.technology = "go_http"
    GoAuthTagger.new(options).perform([Endpoint.new(url, method, [] of Param, details)]).first.tags
  end

  it "counts only a call that wraps the handler or mux and hands the request on" do
    # A registrar taking the mux, an error writer inside a closure and a
    # login handler factory all reply 401 but wrap nothing.
    case_guards.call(169, "/", "GET").should be_empty
    case_guards.call(17, "/account/login", "POST").should be_empty
    case_guards.call(170, "/status", "GET").should be_empty
    case_guards.call(176, "/login", "POST").should be_empty
  end

  it "does not read a pass-through or a non-credential stop as a refusal" do
    case_guards.call(177, "/feed", "GET").should be_empty      # h.ServeHTTP when anonymous
    case_guards.call(178, "/payments", "POST").should be_empty # Idempotency-Key, 400
    case_guards.call(179, "/payments", "GET").should be_empty  # page_token, empty list
    case_guards.call(180, "/logpass", "GET").should be_empty   # blank line before return
    case_guards.call(181, "/else", "GET").should be_empty      # refusal only in an else-if arm
  end

  it "reads method and inline path tests for the route" do
    case_guards.call(193, "/docs", "GET").should be_empty
    case_guards.call(194, "/docs", "POST").map(&.name).should eq(["auth"])
    case_guards.call(198, "/pub/info", "GET").should be_empty
    case_guards.call(199, "/open", "GET").should be_empty
    # A path predicate in the condition is not a permission test: auth, not authz.
    case_guards.call(200, "/priv/info", "GET").map(&.name).should eq(["auth"])
  end

  it "guards a mux only when every use that serves it is wrapped" do
    case_guards.call(204, "/items", "GET").should be_empty
  end

  it "says a setting decides a wrapper applied inside a conditional block" do
    tags = case_guards.call(190, "/admin", "GET")
    tags.map(&.name).should eq(["auth"])
    tags.first.description.should contain("a setting can lift it")
  end
end
