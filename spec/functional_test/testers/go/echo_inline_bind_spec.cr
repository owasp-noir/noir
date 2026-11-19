require "../../func_spec.cr"

# `c.Bind(&in)` in an inline closure reads the bound struct's fields by
# method, as in a named handler: `query` tags on GET, `json` and `form`
# tags on POST, and no generic `body` marker. `c.FormFile` is a form field.
expected_endpoints = [
  Endpoint.new("/named", "POST", [Param.new("name", "", "json"), Param.new("name", "", "form"), Param.new("email", "", "json"), Param.new("email", "", "form")]),
  Endpoint.new("/named", "GET", [Param.new("page", "", "query"), Param.new("search", "", "query")]),
  Endpoint.new("/inline", "POST", [Param.new("name", "", "json"), Param.new("name", "", "form"), Param.new("email", "", "json"), Param.new("email", "", "form")]),
  Endpoint.new("/inline", "GET", [Param.new("page", "", "query"), Param.new("search", "", "query")]),
  Endpoint.new("/upload", "POST", [Param.new("avatar", "", "form")]),
]

tester = FunctionalTester.new("fixtures/go/echo_inline_bind/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "echo inline bind", tags: "functional" do
  it "adds no body marker for a bind target that resolves" do
    tester.app.endpoints.each { |ep| ep.params.map(&.name).should_not contain("body") }
  end
end
