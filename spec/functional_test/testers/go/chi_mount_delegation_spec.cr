require "../../func_spec.cr"

# A mounted function that registers nothing itself but returns another
# function's router (#3581): oapi-codegen's `Handler` returns
# `HandlerWithOptions(...)`, and owncast mounts `handlers.New(h).Handler()`,
# a method on the constructor's result that returns `generated.Handler(s)`.
# Both keep their mount prefix and are not also reported unprefixed.
# `Unmounted` delegates the same way but is never mounted, so `/health`
# stays at the root.
expected_endpoints = [
  Endpoint.new("/api/dynamic", "GET"),
  Endpoint.new("/configured/dynamic", "GET"),
  Endpoint.new("/tenant/nested/dynamic", "GET"),
  Endpoint.new("/api/status", "GET"),
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items", "POST"),
  Endpoint.new("/v2/emoji", "GET"),
  Endpoint.new("/v2/chat", "GET", [Param.new("cursor", "", "json")]),
  Endpoint.new("/health", "GET"),
  Endpoint.new("/tenant/nested/status", "GET"),
  Endpoint.new("/tenant/nested/items", "GET"),
  Endpoint.new("/tenant/nested/items", "POST"),
  Endpoint.new("/configured/status", "GET"),
  Endpoint.new("/configured/items", "GET"),
  Endpoint.new("/configured/items", "POST"),
]

tester = FunctionalTester.new("fixtures/go/chi_mount_delegation/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "chi mount delegation prefix resolution", tags: "functional" do
  it "reads the empty string field only on the mounts that pass it" do
    tester.endpoints.each do |ep|
      if ep.url.starts_with?("/configured/") || ep.url.starts_with?("/tenant/") || ep.url.ends_with?("/dynamic")
        ep.resolution.should eq({"prefix" => "unresolved"})
      else
        ep.resolution.should be_nil
      end
    end
  end
end
