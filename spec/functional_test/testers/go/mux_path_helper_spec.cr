require "../../func_spec.cr"

# Regression (#3578): a gorilla/mux route whose path goes through a
# one-string wrapper (`s.prefixedPath("/version")`, podinfo's shape) was
# dropped, because the mux chain decoder read only string literals. The
# wrapper's runtime prefix is not readable, so the literal is the route.
# `lookupPath("hidden")` returns nothing readable and stays dropped, and
# `http.Get(apiPath("/remote"))` is a client call, not a route.
expected_endpoints = [
  Endpoint.new("/live", "GET"),
  Endpoint.new("/account/info", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/version", "GET"),
  Endpoint.new("/store", "POST"),
  Endpoint.new("/store/{hash}", "GET", [Param.new("hash", "", "path")]),
  Endpoint.new("/api/health", "GET"),
]

tester = FunctionalTester.new("fixtures/go/mux_path_helper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "mux_path_helper route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/version" }.resolution.should eq({"prefix" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/store" }.resolution.should eq({"prefix" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/store/{hash}" }.resolution.should eq({"prefix" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/status" }.resolution.should eq({"prefix" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/live" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/account/info" }.resolution.should eq({"prefix" => "heuristic"})
    tester.endpoints.find! { |ep| ep.url == "/api/health" }.resolution.should be_nil
  end
end
