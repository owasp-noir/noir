require "../../func_spec.cr"

describe "Restify route source attribution" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps the JSRouteExtractor line number for parser endpoints" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/restify_callees/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/users/:id" }
    route_path = endpoint.details.code_paths.first?
    route_path = route_path.should_not be_nil
    route_path.line.should eq(7)
  end
end
