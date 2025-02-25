require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("https://www.hahwul.com/", "GET"),
  Endpoint.new("https://www.hahwul.com/about", "GET"),
  Endpoint.new("https://www.hahwul.com/cullinan", "GET"),
  Endpoint.new("https://www.hahwul.com/phoenix", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/security/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/crystal/", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/zap/", "GET"),
  Endpoint.new("https://www.hahwul.com/form_http", "POST", [Param.new("X-API-Key", "1234", "header"), Param.new("a", "1234", "form")]),
  Endpoint.new("https://www.hahwul.com/json_http", "POST", [Param.new("name", "test", "json"), Param.new("data", "abcd", "json")]),
  Endpoint.new("https://www.hahwul.com/query_http", "GET", [Param.new("q", "1234", "query"), Param.new("Authorization", "abcd", "header")]),
]

tester = FunctionalTester.new("fixtures/etc/file_based/", {
  :techs     => 0,
  :endpoints => extected_endpoints.size,
}, extected_endpoints)

tester.app.options["url"] = YAML::Any.new("https://www.hahwul.com")
tester.test_all
