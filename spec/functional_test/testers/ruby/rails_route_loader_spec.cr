require "../../func_spec.cr"

# config/routes.rb loads every config/routes/*.rb through a Dir.glob loop,
# and those files build paths from `Rails.configuration.api_path` (set in
# config/application.rb) with `+` and as a bare `scope api_path`.
expected_endpoints = [
  Endpoint.new("/init", "GET"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/api/v1/tickets", "GET"),
  Endpoint.new("/api/v1/tickets/:id", "PUT"),
  Endpoint.new("/api/v1/tickets/merge/:id", "POST"),
  Endpoint.new("/api/v1/tickets/search", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/api/v1/tickets/search", "POST"),
  Endpoint.new("/api/v1/ticket_stats", "GET"),
  Endpoint.new("/ticket_overview", "GET"),
  Endpoint.new("/*a", "GET"),
  # overrides.rb: production.rb wins, development.rb alone does not, a
  # conditional assignment and a rebound local resolve to nothing.
  Endpoint.new("/prodbase/a", "GET"),
  Endpoint.new("/devonly/b", "GET"),
  Endpoint.new("/api/v1/scoped", "GET"),
  # The rebound local stays an unresolved interpolation, not `/api/v1/...`.
  Endpoint.new("/{api_path}/stale_interp", "GET"),
]

tester = FunctionalTester.new("fixtures/ruby/rails_route_loader/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the controller action for `root 'c#a'` and `action:` on a resource", tags: "functional" do
  handlers = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler.try(&.name)} }
  handlers["GET /"].should eq("init#index")
  handlers["POST /api/v1/tickets/merge/:id"].should eq("tickets#merge")
  handlers["GET /api/v1/tickets/search"].should eq("tickets#search")
end
