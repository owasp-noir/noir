require "../../func_spec.cr"

# Group prefixes that reach routes through a function boundary: a helper
# that receives its group as an argument (`RegisterUsers(e.Group("/api/v1"))`),
# chi's `r.Route("/users", userRoutes)` naming a function instead of a
# closure, and Fiber's `app.Route(prefix, fn)` / `app.Mount(prefix, subApp)`.
{
  "echo"  => [Endpoint.new("/api/v1/users", "GET", [Param.new("page", "", "query")])],
  "hertz" => [Endpoint.new("/api/v1/users", "GET", [Param.new("page", "", "query")])],
  "chi"   => [Endpoint.new("/users/", "GET"), Endpoint.new("/users/{id}", "GET")],
  "fiber" => [
    Endpoint.new("/r/in", "GET"),
    Endpoint.new("/mnt/micro", "GET"),
    Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  ],
}.each do |fw, expected_endpoints|
  FunctionalTester.new("fixtures/go/group_prefix_#{fw}/", {
    :techs     => 1,
    :endpoints => expected_endpoints.size,
  }, expected_endpoints).perform_tests
end
