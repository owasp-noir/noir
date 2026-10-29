require "../../func_spec.cr"

# Superset's shape: `@expose` routes declared on a shared, never-registered
# `ModelRestApi` base are served under each registered subclass, together
# with the CRUD and `/_info` routes `ModelRestApi` provides, narrowed by
# `include_route_methods`. The base's own name is not a URL.
pk = [Param.new("pk", "", "path")]
column = [Param.new("column_name", "", "path")]
crud = ->(resource : String) do
  [
    Endpoint.new("/api/v1/#{resource}/", "GET"),
    Endpoint.new("/api/v1/#{resource}/", "POST"),
    Endpoint.new("/api/v1/#{resource}/_info", "GET"),
    Endpoint.new("/api/v1/#{resource}/{pk}", "GET", pk),
    Endpoint.new("/api/v1/#{resource}/{pk}", "PUT", pk),
    Endpoint.new("/api/v1/#{resource}/{pk}", "DELETE", pk),
  ]
end
expected_endpoints = crud.call("dashboard") + crud.call("css_template") + [
  Endpoint.new("/api/v1/dashboard/related/{column_name}", "GET", column),
  Endpoint.new("/api/v1/dashboard/distinct/{column_name}", "GET", column),
  Endpoint.new("/api/v1/dashboard/{pk}/charts", "GET", pk),
  # `include_route_methods` names `related` but not `distinct`.
  Endpoint.new("/api/v1/css_template/related/{column_name}", "GET", column),
  # Stacked `@expose` on one method: both are served.
  Endpoint.new("/explore/{id}/", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/explore/", "GET"),
  # `RouteMethod.CRUD_SET` names `list`, not `hidden`.
  Endpoint.new("/dashboard/list/", "GET"),
]

tester = FunctionalTester.new("fixtures/python/flask_appbuilder_inherited/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports nothing under the unregistered base's name", tags: "functional" do
  tester.endpoints.map(&.url).select(&.includes?("baseresourceapi")).should be_empty
end

it "drops a method include_route_methods leaves out", tags: "functional" do
  tester.endpoints.map(&.url).should_not contain("/dashboard/hidden/")
end
