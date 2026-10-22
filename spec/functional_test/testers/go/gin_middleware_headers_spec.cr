require "../../func_spec.cr"

# Header reads in every stdlib form, and the ones middleware makes: an
# `r.Use` middleware's read lands on the routes registered after it, and a
# group's `gin.BasicAuth` adds the Authorization header it checks.
expected_endpoints = [
  Endpoint.new("/early", "GET"),
  Endpoint.new("/echo", "GET", [
    Param.new("X-Forwarded-For", "", "header"),
    Param.new("X-Multi", "", "header"),
    Param.new("Forward", "", "header"),
  ]),
  Endpoint.new("/admin/users", "POST", [
    Param.new("Authorization", "", "header"),
    Param.new("Forward", "", "header"),
  ]),
  Endpoint.new("/after", "GET", [
    Param.new("Forward", "", "header"),
  ]),
  Endpoint.new("/other", "GET"),
]

tester = FunctionalTester.new("fixtures/go/gin_middleware_headers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps middleware header reads off routes outside the middleware", tags: "functional" do
  names = ->(url : String) { tester.endpoints.find! { |e| e.url == url }.params.map(&.name) }
  names.call("/early").should be_empty
  names.call("/other").should be_empty
  names.call("/after").should_not contain("Authorization")
  names.call("/echo").should_not contain("X-Written")
  names.call("/echo").should_not contain("X-Response")
end
