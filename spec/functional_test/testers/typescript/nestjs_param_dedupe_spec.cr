require "../../func_spec.cr"

describe "nestjs param dedupe" do
  tester = FunctionalTester.new("fixtures/typescript/nestjs/", {
    :techs => 1,
  }, [] of Endpoint)

  locator = CodeLocator.instance
  locator.clear_all
  tester.app.detect
  tester.app.analyze

  endpoint = tester.app.endpoints.find { |ep| ep.method == "DELETE" && ep.url == "/users/:id" }

  it "keeps a single path param for DELETE /users/:id" do
    endpoint.should_not be_nil
    if endpoint
      path_params = endpoint.params.select { |param| param.name == "id" && param.param_type == "path" }
      path_params.size.should eq(1)
    end
  end
end
