require "../func_spec.cr"

extected_endpoints = [
  Endpoint.new("https://www.hahwul.com/", "GET"),
  Endpoint.new("https://www.hahwul.com/about", "GET"),
  Endpoint.new("https://www.hahwul.com/cullinan", "GET"),
  Endpoint.new("https://www.hahwul.com/phoenix", "GET"),
  Endpoint.new("https://www.hahwul.com/tag/security/", "GET"),
]

tester = FunctionalTester.new("fixtures/file_based/", {
  :techs     => 0,
  :endpoints => 5,
}, extected_endpoints)

tester.app.options[:url] = "https://www.hahwul.com"
tester.test_all
