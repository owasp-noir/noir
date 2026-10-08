require "../../func_spec.cr"

ws = Endpoint.new("/websocket", "GET")
ws.protocol = "ws"

expected_endpoints = [
  # Method from the same `if` condition; params from the helper it calls.
  Endpoint.new("/api/login", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("username", "", "form"),
  ]),
  # Method from the branch body; JSON keys read by the helper.
  Endpoint.new("/api/settings/set", "PUT", [
    Param.new("brightness", "", "json"),
    Param.new("device_name", "", "json"),
  ]),
  # `#define`d URI.
  Endpoint.new("/api/stats", "GET", [Param.new("page", "", "query")]),
  # `#` (match anything) becomes `*`.
  Endpoint.new("/files/*", "GET"),
  ws,
  # Mongoose 6.x.
  Endpoint.new("/api/v1/status", "GET", [Param.new("verbose", "", "query")]),
  Endpoint.new("/api/v1/sum", "GET", [Param.new("n1", "", "form")]),
]

tester = FunctionalTester.new("fixtures/c/mongoose/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Mongoose route edge cases", tags: "functional" do
  it "skips comments, non-URI matches and the vendored library" do
    urls = tester.app.endpoints.map(&.url)
    urls.should_not contain("/commented")
    urls.should_not contain("/device/rx")
    urls.should_not contain("/vendored")
  end
end
