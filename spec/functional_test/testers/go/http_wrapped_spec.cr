require "../../func_spec.cr"

# net/http ServeMux routes whose handlers are method values on a struct
# local (`handler.createItem`, defined in another file of the package), a
# local bound to a handler factory (`probe := newProbe()`), and a factory
# a middleware is applied to (`fever.Middleware()(fever.NewHandler())`,
# where `NewHandler` returns `http.HandlerFunc(h.serve)`). A mux a called
# function builds (`app.Handle("/v1/", api.NewHandler())`) is a mount, not
# a route.
all_methods = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
expected_endpoints = [
  Endpoint.new("/v1/items", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/v1/items/{itemID}", "GET", [Param.new("itemID", "", "path")]),
  Endpoint.new("/healthcheck", "GET"),
] + all_methods.map { |m| Endpoint.new("/fever/", m) } + all_methods.map { |m| Endpoint.new("/liveness", m) }

tester = FunctionalTester.new("fixtures/go/http_wrapped/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "net/http wrapped handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/http_wrapped"

  it "resolves method values, bound factories and applied middleware to the definition" do
    find = ->(url : String, method : String) { tester.app.endpoints.find! { |ep| ep.url == url && ep.method == method } }
    find.call("/v1/items", "POST").handler.should eq(Handler.new("handler.createItem", "#{base}/api/handlers.go", 11))
    find.call("/healthcheck", "GET").handler.should eq(Handler.new("newProbe()", "#{base}/server/health.go", 10))
    find.call("/fever/", "POST").handler.should eq(Handler.new("h.serve", "#{base}/fever/fever.go", 12))
    find.call("/liveness", "DELETE").handler.should eq(Handler.new("liveness", "#{base}/server/health.go", 5))
  end
end
