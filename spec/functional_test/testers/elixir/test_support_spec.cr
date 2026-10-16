require "../../func_spec.cr"

# Mix compiles `test/support/**` only for MIX_ENV=test (`elixirc_paths(:test)`):
# stub routers, Plug mocks of upstream APIs and Absinthe fixture schemas that
# drive the test suite and never serve traffic. Only the real `lib/` router
# is an endpoint; the Plug, Phoenix and Absinthe decoys under `test/` are not.
tester = FunctionalTester.new("fixtures/elixir/test_support/", {
  :endpoints => 1,
}, [
  Endpoint.new("/health", "GET"),
])

tester.perform_tests

it "reports nothing from the test/ tree", tags: "functional" do
  tester.endpoints.map(&.url).select(&.includes?("should-not-appear")).should be_empty
  tester.endpoints.reject { |endpoint| endpoint.url == "/health" }.should be_empty
end
