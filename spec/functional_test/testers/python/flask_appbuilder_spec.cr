require "../../func_spec.cr"

expected_endpoints = [
  # `resource_name` fills the last segment of the /api/<version>/ default.
  Endpoint.new("/api/v1/database/{pk}/connection", "GET", [Param.new("pk", "", "path")]),
  # `@expose("/")` keeps the trailing slash the blueprint prefix produces.
  Endpoint.new("/api/v1/database/", "POST"),
  # `resource_name` inherited from a base class in another file.
  Endpoint.new("/api/v1/database/{pk}/data", "POST", [Param.new("pk", "", "path")]),
  # `route_base` wins outright and is not prefixed with /api/<version>/.
  Endpoint.new("/annotationlayer/list/", "GET"),
  Endpoint.new("/annotationlayer/{pk}/annotation", "GET", [Param.new("pk", "", "path")]),
  # No resource_name: the class name is the resource, and `version` moves it.
  Endpoint.new("/api/v2/reportapi/summary", "GET"),
  # No route_base on a BaseView subclass: /<class name lowercased>.
  Endpoint.new("/healthview/status", "GET"),
  # Flask-AppBuilder's own IndexView pins route_base = "".
  Endpoint.new("/welcome", "GET"),
]

FunctionalTester.new("fixtures/python/flask_appbuilder/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
