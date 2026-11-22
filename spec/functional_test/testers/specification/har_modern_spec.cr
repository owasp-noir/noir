require "../../func_spec.cr"

websocket_endpoint = Endpoint.new("https://demo.example.com/socket", "GET", [
  Param.new("token", "abc", "query"),
  Param.new("Upgrade", "", "header"),
])
websocket_endpoint.protocol = "ws"

expected_endpoints = [
  Endpoint.new("https://demo.example.com/api/users/{id}", "GET", [
    Param.new("include", "roles", "query"),
    Param.new("id", "", "path"),
    Param.new("Accept", "", "header"),
  ]),
  Endpoint.new("https://demo.example.com/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("profile.email", "", "json"),
    Param.new("Content-Type", "", "header"),
    Param.new("profile", "", "json"),
  ]),
  Endpoint.new("https://demo.example.com/api/search", "POST", [
    Param.new("q", "noir", "form"),
    Param.new("page", "1", "form"),
    Param.new("Content-Type", "", "header"),
  ]),
  websocket_endpoint,
  Endpoint.new("https://demo.example.com/api/users/{id}/avatar", "GET", [
    Param.new("id", "", "path"),
    Param.new("Accept", "", "header"),
  ]),
  Endpoint.new("https://demo.example.com/api/upload", "POST", [
    Param.new("avatar", "", "form"),
    Param.new("caption", "", "form"),
    Param.new("Content-Type", "", "header"),
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
