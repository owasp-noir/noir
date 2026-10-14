require "../../func_spec.cr"

# Every route of `Post("/a", "/b")`, the global `RoutePrefix`, `Group<T>()`
# and `SubGroup<T>` prefixes, `RoutePrefixOverride`, and request properties
# renamed by `[BindFrom("x")]` / `[FromHeader("X")]`.
create_params = [
  Param.new("GroupId", "", "path"),
  Param.new("FirstName", "", "json"),
  Param.new("last_name", "", "json"),
  Param.new("Notify", "", "query"),
  Param.new("X-Tenant", "", "header"),
  Param.new("nick", "", "json"),
]

expected_endpoints = [
  Endpoint.new("/api/users/{GroupId}", "POST", create_params),
  Endpoint.new("/api/members/{GroupId}", "POST", create_params),
  Endpoint.new("/api/admin/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/admin/users/{id}", "HEAD", [Param.new("id", "", "path")]),
  Endpoint.new("/internal/admin/audit/health", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/fastendpoints_prefixes/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "FastEndpoints request property renames", tags: "functional" do
  it "reports the bound name, not the C# property name" do
    create = tester.app.endpoints.find! { |e| e.url == "/api/users/{GroupId}" }
    names = create.params.map(&.name)
    names.should_not contain("LastName")
    names.should_not contain("Tenant")
    names.should_not contain("NickName")
  end
end
