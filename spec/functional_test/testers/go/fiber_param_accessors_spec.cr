require "../../func_spec.cr"

# Fiber's typed query readers, `FormFile`, a cookie read with a default,
# and the struct parsers read as their target's tagged fields:
# `QueryParser` `query` tags, `BodyParser` `json` and `form` tags (no
# generic `body` marker), `ReqHeaderParser` `reqHeader` tags.
expected_endpoints = [
  Endpoint.new("/p01-typed-query", "GET", [Param.new("limit", "", "query"), Param.new("active", "", "query"), Param.new("ratio", "", "query")]),
  Endpoint.new("/p02-queryparser", "GET", [Param.new("page", "", "query"), Param.new("search", "", "query")]),
  Endpoint.new("/p03-bodyparser", "POST", [Param.new("name", "", "json"), Param.new("name", "", "form"), Param.new("email", "", "json"), Param.new("email", "", "form")]),
  Endpoint.new("/p04-cookie-default", "GET", [Param.new("session", "", "cookie")]),
  Endpoint.new("/p05-headerparser", "GET", [Param.new("X-Trace-Id", "", "header")]),
  Endpoint.new("/p06-formfile", "POST", [Param.new("document", "", "form")]),
]

tester = FunctionalTester.new("fixtures/go/fiber_param_accessors/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "fiber param accessors", tags: "functional" do
  it "adds no body marker for a parser target that resolves" do
    tester.app.endpoints.each { |ep| ep.params.map(&.name).should_not contain("body") }
  end
end
