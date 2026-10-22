require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/sign", "GET"),
  Endpoint.new("/sign", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/cookie", "GET"),
  Endpoint.new("/login", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/create_record", "PUT"),
  Endpoint.new("/delete_record", "DELETE", [Param.new("name", "", "json")]),
  Endpoint.new("/get_ip", "GET", [Param.new("X-Forwarded-For", "", "header")]),
  Endpoint.new("/update_record", "POST", [Param.new("page", "", "query"), Param.new("name", "", "json")]),
  Endpoint.new("/search", "QUERY", [Param.new("criteria", "", "json")]),
  Endpoint.new("/lookup", "GET", [Param.new("term", "", "query")]),
  Endpoint.new("/lookup", "QUERY", [Param.new("term", "", "query")]),
  Endpoint.new("/", "GET"),
]

tester = FunctionalTester.new("fixtures/python/flask/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the def each Flask route decorator applies to as the handler", tags: "functional" do
  sign = tester.app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/sign" }
  sign.handler.should eq(Handler.new("sign_sample", "./spec/functional_test/fixtures/python/flask/app.py", 17))
  tester.app.endpoints.count(&.handler.nil?).should eq(0)
end
