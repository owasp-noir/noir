require "../../func_spec.cr"

# UsersApi and PostsApi both name their local router `router`, and AdminApi
# shares `app` with main(); each call belongs only to its own scope's router.
expected_endpoints = [
  Endpoint.new("/health", "GET"),
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/posts/", "GET"),
  Endpoint.new("/posts/{pid}", "DELETE", [Param.new("pid", "", "path")]),
  Endpoint.new("/admin/stats", "GET"),
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
