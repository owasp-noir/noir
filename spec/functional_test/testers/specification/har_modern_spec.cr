require "../../func_spec.cr"

websocket_endpoint = Endpoint.new("https://demo.example.com/socket", "GET", [
  Param.new("token", "abc", "query"),
])
websocket_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("https://demo.example.com/api/users/{id}", "GET", [
    Param.new("include", "roles", "query"),
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("https://demo.example.com/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("profile.email", "", "json"),
  ]),
  Endpoint.new("https://demo.example.com/api/search", "POST", [
    Param.new("q", "noir", "form"),
    Param.new("page", "1", "form"),
  ]),
  websocket_endpoint,
  Endpoint.new("https://demo.example.com/api/users/{id}/avatar", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("https://demo.example.com/api/upload", "POST", [
    Param.new("avatar", "", "form"),
    Param.new("caption", "", "form"),
  ]),
]

instance = FunctionalTester.new("fixtures/specification/har_modern/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("har"),
})

instance.url = "https://demo.example.com"
instance.perform_tests
