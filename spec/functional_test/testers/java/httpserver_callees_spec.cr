require "../../func_spec.cr"

# --include-callee on the JDK HttpServer analyzer. Handler bodies are
# resolved across all three registration forms and walked for 1-hop
# callees:
#   - lambda body            (/users  -> listUsers)
#   - named HttpHandler      (/upload -> storeUpload, via handle())
#   - method reference       (/health -> renderHealth, via health())
expected_endpoints = [
  Endpoint.new("/users", "GET").tap do |ep|
    ep.push_callee(Callee.new("listUsers", line: 16))
  end,
  Endpoint.new("/upload", "GET").tap do |ep|
    ep.push_callee(Callee.new("storeUpload", line: 41))
  end,
  Endpoint.new("/health", "GET").tap do |ep|
    ep.push_callee(Callee.new("renderHealth", line: 32))
  end,
]

FunctionalTester.new("fixtures/java/httpserver_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
