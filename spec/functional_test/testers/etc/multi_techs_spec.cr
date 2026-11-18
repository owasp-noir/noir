require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/update", "POST"),
  Endpoint.new("/query", "POST", [Param.new("query", "", "form")]),
  Endpoint.new("/socket", "GET"),
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/v1/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v1/pets/{petId}", "PUT", [
    Param.new("petId", "", "path"),
    Param.new("breed", "", "json"),
    Param.new("name", "", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/etc/multi_techs/", {
  :techs     => 3,
  :endpoints => 9,
}, expected_endpoints)
tester.perform_tests

describe "multi-tech project origins", tags: "functional" do
  it "keeps each app's GET / and attributes its own params" do
    routes = tester.endpoints.select { |endpoint| endpoint.method == "GET" && endpoint.url == "/" }
    rows = routes.map { |endpoint| {endpoint.details.project, endpoint.params.map(&.name)} }
    rows.sort!.should eq([{"kemal", [] of String}, {"sinatra", ["query"]}])
  end
end
