require "../../func_spec.cr"

describe "APISIX inline upstream and service_id", tags: "functional" do
  it "emits GET /hello and ANY /orders/*" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/specification/apisix_inline/")])
    options["nolog"] = YAML::Any.new(true)

    CodeLocator.instance.clear_all
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.techs.size.should eq(1)
    app.endpoints.map { |endpoint| {endpoint.method, endpoint.url} }.sort!.should eq([
      {"ANY", "/orders/*"},
      {"GET", "/hello"},
    ])
    app.endpoints.each(&.params.should(be_empty))
  end
end
