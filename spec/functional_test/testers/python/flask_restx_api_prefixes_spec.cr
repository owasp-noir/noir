require "../../func_spec.cr"

# flask-restx / flask-restful `Api` prefixes in the libraries' documented
# layouts: namespaces that share a variable name across modules (and with
# the Api), `Api(blueprint)` under `register_blueprint(url_prefix=)`, and
# `Api(prefix=)` built without an app and bound later with `init_app`.
expected_endpoints = [
  Endpoint.new("/api/v1/users/list", "GET"),
  Endpoint.new("/api/v1/orders/list", "GET"),
  Endpoint.new("/api/1/cats/", "GET"),
  Endpoint.new("/api/1/prefix/of/ns2/", "GET"),
  Endpoint.new("/v2/birds/", "GET"),
  Endpoint.new("/v2/swimmers/", "GET"),
  Endpoint.new("/legacy/ping", "GET"),
  Endpoint.new("/api/todos/<int:id>", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/plain", "GET"),
  Endpoint.new("/x/things/list", "GET"),
]

FunctionalTester.new("fixtures/python/flask_restx_api_prefixes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
