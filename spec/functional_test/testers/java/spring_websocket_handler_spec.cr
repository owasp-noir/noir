require "../../func_spec.cr"

# Plain WebSocket handlers registered with
# `WebSocketHandlerRegistry.addHandler(handler, paths...)` (#3268).
chat_endpoint = Endpoint.new("/chat", "GET")
chat_endpoint.protocol = "ws"
ticker_endpoint = Endpoint.new("/ticker", "GET")
ticker_endpoint.protocol = "ws"
ticker_legacy_endpoint = Endpoint.new("/ticker/legacy", "GET")
ticker_legacy_endpoint.protocol = "ws"

expected_endpoints = [Endpoint.new("/health", "GET"), chat_endpoint, ticker_endpoint, ticker_legacy_endpoint]

# The commented-out `addHandler(oldHandler, "/old")` is not a route.
FunctionalTester.new("fixtures/java/spring_websocket_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Spring addHandler CORS", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "flags a handler that accepts every origin" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/spring_websocket_handler/")])
    options["all_taggers"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    cors = ->(url : String) { app.endpoints.find!(&.url.==(url)).tags.select { |tag| tag.name == "cors" }.map(&.description) }
    cors.call("/chat").should eq(["Permissive CORS (WebSocket/STOMP endpoint config) — addHandler(\"/chat\") allows all origins (*)."])
    cors.call("/ticker").should be_empty
  end
end
