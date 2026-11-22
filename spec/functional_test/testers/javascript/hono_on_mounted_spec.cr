require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# `sub.on(method, path, handler)` on a sub-app takes the prefix the sub-app
# is mounted under, like every other verb call on it. An event emitter's
# `events.on('get', '/room/1', cb)` in the same file is not a route.
expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/fixed/counter/total", "GET", [Param.new("unit", "", "query")]),
  Endpoint.new("/seasonal/counter/total", "GET", [Param.new("unit", "", "query")]),
  Endpoint.new("/books/", "GET"),
  Endpoint.new("/books/:id", "PUT", [Param.new("id", "", "path"), Param.new("title", "", "json")]),
  Endpoint.new("/books/:id", "PATCH", [Param.new("id", "", "path"), Param.new("title", "", "json")]),
  Endpoint.new("/books/", "POST", [Param.new("isbn", "", "query")]),
  Endpoint.new("/books/import", "POST", [Param.new("isbn", "", "query")]),
  Endpoint.new("/api/auth/*", "GET"),
  Endpoint.new("/api/auth/*", "POST"),
]

tester = FunctionalTester.new("fixtures/javascript/hono_on_mounted/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

describe "Hono on() routes of a mounted sub-app", tags: "functional" do
  it "resolves the handler and its callees, and traces under the mount prefix" do
    endpoints = tester.app.endpoints
    endpoints.find!(&.url.==("/fixed/counter/total")).resolution.should be_nil
    endpoints.find!(&.url.==("/seasonal/counter/total")).resolution.should eq({"prefix" => "heuristic"})
    put = endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/books/:id" }
    put.handler.try(&.name).should eq("closure")
    put.callees.map(&.name).should contain("c.req.json")

    import = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/books/import" }
    import.handler.try { |h| {h.name, File.basename(h.path.to_s), h.line} }.should eq({"saveBook", "handlers.ts", 3})

    Noir::CLI::Inspect.trace(endpoints, "PATCH", "/books/7").map { |m| {m.endpoint.url, m.matched_by} }.should eq([{"/books/:id", "pattern"}])
    Noir::CLI::Inspect.trace(endpoints, "PATCH", "/7").should be_empty
    Noir::CLI::Inspect.reach(endpoints, "src/handlers.ts", nil, false).map { |row| "#{row.method} #{row.url}" }.sort!.should eq(["POST /books/", "POST /books/import"])
  end
end
