require "../../func_spec.cr"

# Apache Pekko HTTP (`org.apache.pekko.http`) shares the Akka HTTP DSL and
# is detected and analyzed as `scala_akka`.
expected_endpoints = [
  Endpoint.new("/hello", "GET"),
  Endpoint.new("/api/items/{itemId}", "GET", [
    Param.new("itemId", "", "path"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/api/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("X-API-Key", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/scala/pekko/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
