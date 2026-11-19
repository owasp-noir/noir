require "../../func_spec.cr"

# Permit lists reached through `params.slice(...)`, `params[:post]`,
# `.require(...).require(...)` and a leading-dot chain over three lines.
expected_endpoints = [
  Endpoint.new("/timeline", "GET", [Param.new("limit", "", "query"), Param.new("max_id", "", "query")]),
  Endpoint.new("/posts", "POST", [Param.new("title", "", "json"), Param.new("body", "", "json")]),
  Endpoint.new("/posts/:id", "PATCH", [Param.new("id", "", "path"), Param.new("title", "", "json"), Param.new("published", "", "json")]),
  Endpoint.new("/comments", "POST", [Param.new("text", "", "json"), Param.new("author", "", "json")]),
]

tester = FunctionalTester.new("fixtures/ruby/rails_permit_chains/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "does not report the permit list's container key as a field", tags: "functional" do
  names = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.params.map(&.name).sort!} }
  names["POST /posts"].should eq(%w[body title])
  names["PATCH /posts/:id"].should eq(%w[id published title])
  names["POST /comments"].should eq(%w[author text])
end
