require "../../func_spec.cr"

# `enableVersioning({ type: URI, prefix: `${CONTEXT_PATH}v`, defaultVersion: '1' })`
# in apps/api: a controller with no version of its own serves `/v1`, one
# with `version: '2'` serves `/v2`, VERSION_NEUTRAL none. The context path
# is the deployment's (empty unless configured). apps/webhook has its own
# bootstrap with no versioning, so its hard-coded `v1/` is not doubled.
expected_endpoints = [
  Endpoint.new("/vprocess.env.VERSION/status/release", "GET"),
  Endpoint.new("/events", "GET"),
  Endpoint.new("/v1/both", "GET"),
  Endpoint.new("/both", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/v1/auth/login", "POST", [Param.new("body", "", "body")]),
  Endpoint.new("/v2/topics", "GET"),
  Endpoint.new("/.well-known/resource", "GET"),
  Endpoint.new("/v1/health-check", "GET"),
]

tester = FunctionalTester.new("fixtures/typescript/nestjs_default_version/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "nestjs_default_version route resolution", tags: "functional" do
  it "records the evidence for each reported route" do
    tester.endpoints.find! { |ep| ep.url == "/vprocess.env.VERSION/status/release" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/v1/auth/login" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/v2/topics" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/v1/both" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/both" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/events" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/status" }.resolution.should eq({"prefix" => "unresolved"})
    tester.endpoints.find! { |ep| ep.url == "/.well-known/resource" }.resolution.should be_nil
    tester.endpoints.find! { |ep| ep.url == "/v1/health-check" }.resolution.should be_nil
  end
end
