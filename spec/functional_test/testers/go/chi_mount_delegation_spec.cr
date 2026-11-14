require "../../func_spec.cr"

# A mounted function that registers nothing itself but returns another
# function's router (#3581): oapi-codegen's `Handler` returns
# `HandlerWithOptions(...)`, and owncast mounts `handlers.New(h).Handler()`,
# a method on the constructor's result that returns `generated.Handler(s)`.
# Both keep their mount prefix and are not also reported unprefixed.
# `Unmounted` delegates the same way but is never mounted, so `/health`
# stays at the root.
expected_endpoints = [
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/v2/emoji", "GET"),
  Endpoint.new("/v2/chat", "GET"),
  Endpoint.new("/health", "GET"),
]

tester = FunctionalTester.new("fixtures/go/chi_mount_delegation/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

# The mount prefix is read; the generated base between it and the tail is
# not, so the mark survives the Mount expansion (#3567).
describe "chi mount delegation prefix resolution", tags: "functional" do
  it "keeps the mark on mounted generated routes, and not on a literal one" do
    tester.endpoints.reject(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.should eq(["GET /health"])
  end
end
