require "../../func_spec.cr"

# UsersApi and PostsApi both name their local router `router`, AdminApi
# shares `app` with main(), and the ExportRoutes mixin shares `reports`;
# each call belongs only to its own scope's router. The endpoint count
# check catches any route leaking into another router's prefix.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/posts/{pid}", "DELETE", [Param.new("pid", "", "path")]),
  Endpoint.new("/admin/stats", "GET"),
  Endpoint.new("/reports/daily", "GET"),
  # ExportRoutes is never mounted, so its mixin-local `reports` stays at root.
  Endpoint.new("/export", "GET"),
  # `server.router.get` is Server's field, not UsersApi/PostsApi's local.
  Endpoint.new("/version", "GET"),
]

tester = FunctionalTester.new("fixtures/dart/shelf_scoped_router/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Shelf router variable scoping", tags: "functional" do
  it "attributes each route to its own class's line only" do
    lines = tester.app.endpoints.to_h { |e| {"#{e.method} #{e.url}", e.details.code_paths.map(&.line)} }
    lines["GET /users/"].should eq [7]
    lines["GET /posts/"].should eq [16]
  end
end
