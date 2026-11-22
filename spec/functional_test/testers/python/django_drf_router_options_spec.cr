require "../../func_spec.cr"

# A DRF router built with `trailing_slash=False` serves its routes without
# the trailing `/`, and a viewset's `http_method_names` limits the verbs
# its ModelViewSet base would otherwise expose.
extracted_endpoints = [
  Endpoint.new("/extra", "GET"),
  Endpoint.new("/extra", "POST"),
  Endpoint.new("/extra/{pk}", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/tags", "POST"),
  Endpoint.new("/tags/{pk}", "GET", [Param.new("pk", "", "path")]),
]

tester = FunctionalTester.new("fixtures/python/django_drf_router_options/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints)
tester.perform_tests

describe "django_drf_router_options route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/extra" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/extra/{pk}" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/tags" }.resolution.should be_nil
  end
end
