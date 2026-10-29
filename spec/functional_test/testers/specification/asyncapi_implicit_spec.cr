require "../../func_spec.cr"

describe "AsyncAPI 3 implicit channel messages", tags: "functional" do
  it "uses channel messages, multi-format schemas, and ws query bindings" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/specification/asyncapi/v3_implicit/")])
    options["nolog"] = YAML::Any.new(true)

    CodeLocator.instance.clear_all
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.techs.size.should eq(1)
    app.endpoints.size.should eq(2)

    params = ->(method : String, url : String) do
      app.endpoints.find! { |endpoint| endpoint.method == method && endpoint.url == url }
        .params.map { |param| {param.name, param.param_type} }.sort!
    end

    params.call("SEND", "/rooms/{roomId}").should eq([
      {"heartbeat", "query"},
      {"roomId", "path"},
      {"text", "json"},
    ])
    params.call("RECEIVE", "/shop.orders.created").should eq([{"orderId", "json"}])
  end
end
