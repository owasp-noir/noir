require "../../func_spec.cr"

describe "Reitit spec keys and request content", tags: "functional" do
  it "reads :req-un query keys and JSON body fields from :request" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/clojure/reitit_request/")])
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

    params.call("GET", "/minus").should eq([{"x", "query"}, {"y", "query"}, {"z", "query"}])
    params.call("GET", "/malli").should eq([{"x", "query"}, {"y", "query"}])
    params.call("POST", "/pizza").should eq([{"color", "json"}, {"pineapple", "json"}])
  end
end
