require "../../func_spec.cr"

# net/http ServeMux routes whose handlers are method values on a struct
# local (`handler.createItem`, defined in another file of the package), a
# local bound to a handler factory (`probe := newProbe()`), and a factory
# a middleware is applied to (`fever.Middleware()(fever.NewHandler())`,
# where `NewHandler` returns `http.HandlerFunc(h.serve)`). A mux a called
# function builds (`app.Handle("/v1/", api.NewHandler())`) is a mount, not
# a route. A wrapper around a factory call (`auth(handleRun())`) answers
# with what the factory builds.
#
# Params are read from the resolved definition and the helpers it calls,
# in its own or an imported package: a helper's parameter bound to the
# literal passed (`request.QueryFlag(r, "full")` reading
# `r.URL.Query().Get(param)`, or a local holding `r.URL.Query()`), package
# string constants
# (`r.PostForm[paramTagsAdd]`), and a decoded body's struct fields. A
# response writer of another package (`response.Unauthorized(w, r)`) and a
# header read off an upstream response (`resp.Header.Get`) are not inputs.
# A loop over a string list (`for _, name := range [...]string{...}`)
# reads each name.
all_methods = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
expected_endpoints = [
  Endpoint.new("/v1/items", "POST", [Param.new("title", "", "json"), Param.new("archived", "", "json")]),
  Endpoint.new("/v1/items/{itemID}", "GET", [Param.new("itemID", "", "path"), Param.new("full", "", "query"), Param.new("verbose", "", "query")]),
  Endpoint.new("/jobs/run", "POST", [Param.new("script", "", "json"), Param.new("Cwd", "", "json")]),
  Endpoint.new("/reader/login", "POST", [Param.new("Email", "", "form")]),
  Endpoint.new("/reader/edit", "POST", [Param.new("a", "", "form"), Param.new("i", "", "form")]),
  Endpoint.new("/healthcheck", "GET"),
  Endpoint.new("/login", "GET"),
  Endpoint.new("/items/{id}/remove", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/share/{code}", "GET", [Param.new("code", "", "path")]),
  Endpoint.new("/static/{file}", "GET", [Param.new("file", "", "path"), Param.new("Range", "", "header"), Param.new("Accept", "", "header")]),
  Endpoint.new("/fever/", "POST", [Param.new("groups", "", "query"), Param.new("mark", "", "form")]),
] + (all_methods - ["POST"]).map { |m| Endpoint.new("/fever/", m) } + all_methods.flat_map { |m| [Endpoint.new("/liveness", m), Endpoint.new("/", m)] }

tester = FunctionalTester.new("fixtures/go/http_wrapped/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "net/http wrapped handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/http_wrapped"
  find = ->(url : String, method : String) { tester.app.endpoints.find! { |ep| ep.url == url && ep.method == method } }

  it "resolves method values, bound factories and applied middleware to the definition" do
    find.call("/v1/items", "POST").handler.should eq(Handler.new("handler.createItem", "#{base}/api/handlers.go", 12))
    find.call("/healthcheck", "GET").handler.should eq(Handler.new("newProbe()", "#{base}/server/health.go", 10))
    find.call("/fever/", "POST").handler.should eq(Handler.new("h.serve", "#{base}/fever/fever.go", 12))
    find.call("/liveness", "DELETE").handler.should eq(Handler.new("liveness", "#{base}/server/health.go", 5))
    find.call("/jobs/run", "POST").handler.should eq(Handler.new("handleRun", "#{base}/jobs/jobs.go", 21))
  end

  it "keeps response negotiation and upstream response headers out of params" do
    names = find.call("/v1/items/{itemID}", "GET").params.map(&.name)
    names.should_not contain("Accept-Encoding")
    names.should_not contain("Content-Type")
    find.call("/v1/items", "POST").params.map(&.name).should_not contain("body")
  end
end

# Mounts wrapped in middleware (`requireAuth(api)`) are mounts too; a
# factory whose handler merely calls `http.Get("/upstream")` is not a
# router; a package constant shadowed by a local or range variable, and an
# outbound client helper, add no params.
cases = FunctionalTester.new("fixtures/go/http_guard_cases/", {:techs => 1}, [
  Endpoint.new("/items", "GET"),
  Endpoint.new("/search", "GET", [Param.new("a", "", "query"), Param.new("b", "", "query")]),
])
cases.perform_tests

describe "net/http lookalikes", tags: "functional" do
  it "keeps mounts out and reads no shadowed constant or outbound read" do
    urls = cases.app.endpoints.map(&.url)
    %w[/api/ /legacy/ /docs/ /x/].each { |mount| urls.should_not contain(mount) }
    search = cases.app.endpoints.find! { |ep| ep.url == "/search" }
    search.params.map(&.name).should_not contain("title")
    search.params.map(&.name).should_not contain("ETag")
    search.params.map(&.name).should_not contain("upstream_page")
    cases.app.endpoints.find! { |ep| ep.url == "/hdr" }.params.should be_empty
  end
end
