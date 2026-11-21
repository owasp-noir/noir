require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/hello", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/api/v1/status", "GET"),
  Endpoint.new("/submit", "POST", [
    Param.new("name", "", "form"),
    Param.new("label", "", "form"),
    Param.new("page", "", "query"),
    Param.new("id", "", "json"),
    Param.new("X-Token", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/delete-me", "DELETE"),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/widgets/{widget_id}", "GET", [
    Param.new("widget_id", "", "path"),
  ]),
]

tester = FunctionalTester.new("fixtures/python/http_server/", {
  :techs     => 1,
  :endpoints => 7,
}, expected_endpoints)
tester.perform_tests

it "keeps http.server form fields and query parameters separate", tags: "functional" do
  submit = tester.endpoints.find! { |endpoint| endpoint.url == "/submit" && endpoint.method == "POST" }
  submit.params.select(&.param_type.==("query")).map(&.name).should eq(["page"])
  submit.params.select(&.param_type.==("form")).map(&.name).sort!.should eq(["label", "name"])
end
