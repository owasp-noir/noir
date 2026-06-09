require "../../func_spec.cr"

chat_ws_endpoint = Endpoint.new("/socket/chat/{roomId}", "GET", [
  Param.new("roomId", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("StompEndpointRegistry.addEndpoint", line: 13))
end
chat_ws_endpoint.protocol = "ws"

portfolio_ws_endpoint = Endpoint.new("/portfolio", "GET").tap do |ep|
  ep.push_callee(Callee.new("StompEndpointRegistry.addEndpoint", line: 13))
end
portfolio_ws_endpoint.protocol = "ws"

chat_send_endpoint = Endpoint.new("/app/chat/send/{roomId}", "SEND", [
  Param.new("text", "", "json"),
  Param.new("author", "", "json"),
  Param.new("roomId", "", "path"),
]).tap do |ep|
  ep.protocol = "ws"
  ep.push_callee(Callee.new("chatService.send", line: 14))
end

chat_presence_endpoint = Endpoint.new("/app/chat/presence/{roomId}", "SUBSCRIBE", [
  Param.new("roomId", "", "path"),
]).tap do |ep|
  ep.protocol = "ws"
  ep.push_callee(Callee.new("chatService.presence", line: 19))
end

chat_echo_endpoint = Endpoint.new("/app/chat/echo", "SEND", [
  Param.new("text", "", "json"),
  Param.new("author", "", "json"),
]).tap do |ep|
  ep.protocol = "ws"
  ep.push_callee(Callee.new("ChatMessageController.echo", line: 22))
end

expected_endpoints = [
  chat_ws_endpoint,
  portfolio_ws_endpoint,
  chat_send_endpoint,
  chat_presence_endpoint,
  chat_echo_endpoint,
]

FunctionalTester.new("fixtures/kotlin/spring_websocket/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "--ai-context on Kotlin Spring websocket fixtures" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces STOMP response destinations as endpoint signals" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_websocket/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "SEND" && ep.url == "/app/chat/send/{roomId}" }
    endpoint.tags.map { |tag| {tag.name, tag.description} }.should contain({"stomp-send-to", "/topic/chat/{roomId}"})

    context = endpoint.ai_context
    context = context.should_not be_nil
    context.signals.map(&.name).should contain("stomp-send-to")
    context.signals.map(&.description).should contain("/topic/chat/{roomId}")

    echo_endpoint = app.endpoints.find! { |ep| ep.method == "SEND" && ep.url == "/app/chat/echo" }
    echo_endpoint.callees.map(&.name).should contain("ChatMessageController.echo")

    echo_context = echo_endpoint.ai_context
    echo_context = echo_context.should_not be_nil
    echo_context.signals.map(&.description).should contain("/topic/echo")
  end

  it "surfaces permissive WebSocket CORS config on handshake endpoints" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_websocket/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/portfolio" }
    cors_tag = endpoint.tags.find { |tag| tag.name == "cors" }
    cors_tag.should_not be_nil
    cors_tag.not_nil!.description.should contain("WebSocket/STOMP endpoint config")
    cors_tag.not_nil!.description.should contain("addEndpoint(\"/portfolio\")")

    context = endpoint.ai_context
    context = context.should_not be_nil
    context.signals.map(&.kind).should contain("cors")
    context.signals.map(&.description).should contain(cors_tag.not_nil!.description)
    context.sources.map(&.kind).should contain("cors_policy")
    context.sources.map(&.name).should contain(cors_tag.not_nil!.description)
  end
end
