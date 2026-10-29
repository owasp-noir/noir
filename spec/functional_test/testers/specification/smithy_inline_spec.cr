require "../../func_spec.cr"

describe "Smithy IDL 2 inline input", tags: "functional" do
  it "maps inline structures and resource targets onto body, query, and path params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/specification/smithy_inline/")])
    options["nolog"] = YAML::Any.new(true)

    CodeLocator.instance.clear_all
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.techs.size.should eq(1)
    app.endpoints.size.should eq(3)

    params = ->(method : String, url : String) do
      app.endpoints.find! { |endpoint| endpoint.method == method && endpoint.url == url }
        .params.map { |param| {param.name, param.param_type} }.sort!
    end

    params.call("POST", "/order").should eq([{"coffeeType", "json"}, {"note", "json"}])
    params.call("GET", "/order/{id}").should eq([{"id", "path"}])
    params.call("POST", "/plain").should eq([{"coffeeType", "json"}, {"verbose", "query"}])
  end
end
