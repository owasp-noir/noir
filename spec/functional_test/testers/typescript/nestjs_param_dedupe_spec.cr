require "../../func_spec.cr"

describe "nestjs param dedupe" do
  tester = FunctionalTester.new("fixtures/typescript/nestjs/", {
    :techs => 1,
  }, [] of Endpoint)

  # The lookup lives inside the example: `FunctionalTester` scans lazily on
  # first use, so driving `detect`/`analyze` out here would put the scan back at
  # collection time — where a raise takes the whole run down and reports nothing.
  it "keeps a single path param for DELETE /users/:id" do
    endpoint = tester.endpoints.find { |ep| ep.method == "DELETE" && ep.url == "/users/:id" }
    endpoint.should_not be_nil
    if endpoint
      path_params = endpoint.params.select { |param| param.name == "id" && param.param_type == "path" }
      path_params.size.should eq(1)
    end
  end
end
