require "../../func_spec.cr"

# Astro serves every script file under `src/pages/` as an endpoint, not
# only those under `api/`, and a param keeps its file-name suffix.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/rss.xml", "GET"),
  Endpoint.new("/auth/signin", "POST"),
  Endpoint.new("/api/posts/{id}.json", "GET", [
    Param.new("id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/javascript/astro_endpoints/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
