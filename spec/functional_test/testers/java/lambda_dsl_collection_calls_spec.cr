require "../../func_spec.cr"

# `Map#put`, `ResultSet#get` and `Config#get` share the verb names of Helidon
# SE, Spark and Javalin. A first argument that is not path-shaped (no leading
# `/` or `*`) only counts as a route when a lambda or method-reference
# handler comes with it, so the collection calls in the fixture must not
# surface as `PUT /br`, `GET /ID`, `GET /db.url`, `PUT /csrf`, ... while the
# slash-less lambda and method-reference routes are kept.
expected_endpoints = [
  Endpoint.new("/helidon/health", "GET"),
  Endpoint.new("/helidon/slashless", "GET"),
  Endpoint.new("/helidon/by-ref", "POST"),
  Endpoint.new("/spark/hello", "GET"),
  Endpoint.new("/spark/slashless", "GET"),
  Endpoint.new("/javalin/users", "GET"),
  Endpoint.new("/javalin/ping", "GET"),
]

FunctionalTester.new("fixtures/java/lambda_dsl_collection_calls/", {
  :techs     => 3,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
