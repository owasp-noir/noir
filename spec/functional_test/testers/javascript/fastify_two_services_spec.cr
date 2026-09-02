require "../../func_spec.cr"

# Two Fastify services in one repo, both serving `GET /items/:id`.
#
# The auxiliary `fastify.route({…})` pass guarded against re-emitting a route
# with `result.any? { |e| e.url == url && e.method == method }`, and `result`
# is the accumulator for the whole analyzer run, not the file being read. The
# second service's declaration was therefore dropped outright — never reaching
# the optimizer, so its file was not merged in as a second code path either.
# Which of the two survived came down to the order the worker pool handed the
# files over, so the same scan named a different source file between runs.
expected_endpoints = [
  Endpoint.new("/items/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/items/:id", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/items/:id", "DELETE", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/javascript/fastify_two_services/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps both services as code paths of the shared route" do
  shared = tester.app.endpoints.find { |endpoint| endpoint.url == "/items/:id" && endpoint.method == "GET" }
  shared.should_not be_nil
  paths = shared.try(&.details.code_paths.map { |code_path| File.basename(File.dirname(code_path.path)) }) || [] of String
  paths.sort.should eq(["service-a", "service-b"])
end
