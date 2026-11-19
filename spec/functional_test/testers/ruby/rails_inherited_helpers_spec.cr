require "../../func_spec.cr"

# Params read by a helper the controller inherits (`Api::BaseController#limit_param`)
# or includes (`Sortable#sort_options`), called from the action or from one
# of its own helpers.
expected_endpoints = [
  Endpoint.new("/api/v1/blocks", "GET", [Param.new("max_id", "", "query"), Param.new("since_id", "", "query"), Param.new("limit", "", "query")]),
  Endpoint.new("/api/v1/mutes", "GET", [Param.new("limit", "", "query")]),
  Endpoint.new("/api/v1/search", "GET", [Param.new("q", "", "query"), Param.new("sort_by", "", "query"), Param.new("sort_dir", "", "query")]),
]

tester = FunctionalTester.new("fixtures/ruby/rails_inherited_helpers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "attributes only the inherited helpers an action calls", tags: "functional" do
  names = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.params.map(&.name).sort!} }
  names["GET /api/v1/mutes"].should eq(%w[limit])
  names["GET /api/v1/search"].should eq(%w[q sort_by sort_dir])
end
