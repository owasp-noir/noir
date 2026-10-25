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
    guards.call("server/routes.go", 18, "/fever/", "GET").should eq(["Protected by Go middleware fever.Middleware (verified from its body: refuses anonymous callers)"])
  end

  it "reads a path predicate in the refusal's condition for the route" do
    guards.call("ui/ui.go", 14, "/items/{id}/remove", "POST").should eq(["Protected by Go middleware session.handle (verified from its body: refuses anonymous callers)"])
    guards.call("ui/ui.go", 13, "/login", "GET").should be_empty
    guards.call("ui/ui.go", 15, "/share/{code}", "GET").should be_empty
    guards.call("ui/ui.go", 16, "/static/{file}", "GET").should be_empty
  end

  it "leaves routes no refusing wrapper reaches open" do
    guards.call("server/routes.go", 28, "/liveness", "GET").should be_empty
    guards.call("server/routes.go", 16, "/healthcheck", "GET").should be_empty
  end
end
