require "../../func_spec.cr"

# Paths built through another package's constant and a one-string wrapper
# whose definition returns its argument (`router.Group(conf.BaseUri(
# config.ApiUri))`, `router.GET(conf.BaseUri("/livez"), isLive)`) or adds a
# fixed prefix (`config.Versioned("/status")` -> `/v2/status`). The API
# group is a package-level var assigned in another file and handed to
# router builders in another package. Inline closures are their own
# handlers; a closure bound to a local name is named after it.
expected_endpoints = [
  Endpoint.new("/api/v1/photos/:uid", "GET", [Param.new("uid", "", "path")]),
  Endpoint.new("/api/v1/version", "GET"),
  Endpoint.new("/s/:token", "GET", [Param.new("token", "", "path")]),
  Endpoint.new("/livez", "GET"),
  Endpoint.new("/v2/status", "GET"),
]

tester = FunctionalTester.new("fixtures/go/gin_wrapped_paths/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names inline and locally bound closures as handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/gin_wrapped_paths"
  photo = tester.app.endpoints.find! { |ep| ep.url == "/api/v1/photos/:uid" }
  photo.handler.should eq(Handler.new("closure", "#{base}/api/photos.go", 8))
  live = tester.app.endpoints.find! { |ep| ep.url == "/livez" }
  live.handler.should eq(Handler.new("isLive", "#{base}/server/routes.go", 14))
end
