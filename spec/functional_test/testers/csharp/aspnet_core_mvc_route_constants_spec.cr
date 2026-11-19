require "../../func_spec.cr"

# Route templates that are constants the scan declares — `ApiRoutes.X`, a
# same-class `const`, `Const + "/x"` and constants built from other
# constants — are read at the action and the controller alike. One the scan
# cannot read is still reported, tagged `unresolved-route`; at the
# controller its unreadable operands become placeholders.
expected_endpoints = [
  Endpoint.new("/api/v1/posts", "GET"),
  Endpoint.new("/api/v1/posts/{postId}", "GET", [Param.new("postId", "", "path")]),
  Endpoint.new("/api/v1/posts", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/v1/posts/{postId}", "DELETE", [Param.new("postId", "", "path")]),
  Endpoint.new("/api/v1/tags", "GET"),
  Endpoint.new("/api/v1/tags/{tagId}", "GET", [Param.new("tagId", "", "path")]),
  Endpoint.new("/api/v1/tags/{tagId}/rename", "PUT", [Param.new("tagId", "", "path"), Param.new("name", "", "json")]),
  Endpoint.new("/api/v1/tags/{tagId}/merge", "POST", [Param.new("tagId", "", "path")]),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/interp", "GET"),
  Endpoint.new("/api/concat", "GET"),
  Endpoint.new("/Legacy/Find", "GET"),
  Endpoint.new("/Legacy/Index", "ANY"),
  Endpoint.new("/{cryptoCode}/{BIP21EndpointKey}", "POST", [
    Param.new("cryptoCode", "", "path"), Param.new("BIP21EndpointKey", "", "path"),
  ]),
  Endpoint.new("/{Base}/status", "GET", [Param.new("Base", "", "path")]),
  Endpoint.new("/external/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_route_constants/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC route constants", tags: "functional" do
  it "tags only the routes it cannot read" do
    tagged = tester.app.endpoints.select { |ep| ep.tags.any?(&.name.==("unresolved-route")) }
    tagged.map { |ep| "#{ep.method} #{ep.url}" }.sort!.should eq([
      "ANY /Legacy/Index", "GET /Legacy/Find", "GET /{Base}/status", "POST /{cryptoCode}/{BIP21EndpointKey}",
    ])
    tester.app.endpoints.map(&.url).should_not contain("/")
  end
end
