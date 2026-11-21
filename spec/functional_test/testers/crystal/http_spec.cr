require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET"),
  Endpoint.new("/api/items", "GET", [Param.new("filter", "", "query")]),
  Endpoint.new("/api/catalog", "GET", [Param.new("filter", "", "query")]),
  Endpoint.new("/guide", "GET"),
  Endpoint.new("/docs", "GET"),
  Endpoint.new("/after-heredoc", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
    Param.new("page", "", "query"),
    Param.new("X-API-KEY", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
]

tester = FunctionalTester.new("fixtures/crystal/http/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Crystal HTTP case path aliases", tags: "functional" do
  it "attributes both aliases and their params to their shared branch" do
    ["/api/items", "/api/catalog"].each do |url|
      endpoint = tester.endpoints.find! { |ep| ep.url == url && ep.method == "GET" }
      endpoint.details.code_paths.any? { |info| info.path.ends_with?("/crystal/http/src/testapp.cr") && info.line == 21 }.should be_true
      endpoint.params.map(&.name).sort!.should eq(["filter", "sort"])
    end
    after_heredoc = tester.endpoints.find! { |ep| ep.url == "/after-heredoc" && ep.method == "GET" }
    after_heredoc.params.should be_empty
    ["/guide", "/docs"].each do |url|
      tester.endpoints.find! { |ep| ep.url == url && ep.method == "GET" }.params.should be_empty
    end
  end
end
