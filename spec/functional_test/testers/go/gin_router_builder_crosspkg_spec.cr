require "../../func_spec"

expected = [
  Endpoint.new("/api/v1/users/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v1/users", "POST"),
  Endpoint.new("/api/v1/posts/:slug", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/api/v1/health/live", "GET"),
  Endpoint.new("/sample/draft/today", "GET"),
]
["", "/public", "/ops"].each do |prefix|
  %w[GET POST].each { |verb| expected << Endpoint.new("#{prefix}/calendar/events", verb) }
end
tester = FunctionalTester.new("fixtures/go/gin_router_builder_crosspkg/", {:techs => 1, :endpoints => expected.size}, expected)
tester.perform_tests

describe "Gin cross-package router fields", tags: "functional" do
  it "marks only the branches that depend on the environment" do
    tester.endpoints.each do |ep|
      mark = case ep.url
             when "/ops/calendar/events" then {"prefix" => "heuristic"}
             when "/calendar/events"     then {"prefix" => "unresolved"}
             end
      ep.resolution.should eq(mark)
    end
  end
end
