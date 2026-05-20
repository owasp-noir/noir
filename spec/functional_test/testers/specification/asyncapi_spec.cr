require "../../func_spec.cr"

# AsyncAPI 2.x — YAML — Kafka channel with publish + subscribe
v2_yaml_endpoints = [
  Endpoint.new("/user/signedup", "PUBLISH", [
    Param.new("userId", "", "json"),
    Param.new("displayName", "", "json"),
  ]),
  Endpoint.new("/user/signedup", "SUBSCRIBE", [
    Param.new("id", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/asyncapi/v2_yaml/", {
  :techs     => 1,
  :endpoints => v2_yaml_endpoints.size,
}, v2_yaml_endpoints).perform_tests

# AsyncAPI 2.x — JSON — WebSocket publish
v2_json_endpoints = [
  Endpoint.new("/chat/messages", "PUBLISH", [
    Param.new("text", "", "json"),
    Param.new("author", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/asyncapi/v2_json/", {
  :techs     => 1,
  :endpoints => v2_json_endpoints.size,
}, v2_json_endpoints).perform_tests

# AsyncAPI 3.x — YAML — MQTT send + receive with channel address
v3_yaml_endpoints = [
  Endpoint.new("/order/created", "SEND", [
    Param.new("orderId", "", "json"),
    Param.new("total", "", "json"),
  ]),
  Endpoint.new("/order/shipped", "RECEIVE", [
    Param.new("orderId", "", "json"),
    Param.new("trackingNumber", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/asyncapi/v3_yaml/", {
  :techs     => 1,
  :endpoints => v3_yaml_endpoints.size,
}, v3_yaml_endpoints).perform_tests

# AsyncAPI 3.x — JSON — AMQP send
v3_json_endpoints = [
  Endpoint.new("/notifications/inbox", "SEND", [
    Param.new("title", "", "json"),
    Param.new("body", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/asyncapi/v3_json/", {
  :techs     => 1,
  :endpoints => v3_json_endpoints.size,
}, v3_json_endpoints).perform_tests
