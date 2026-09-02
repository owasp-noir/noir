require "../../func_spec.cr"

# Two NestJS applications under one scan base, each with its own
# `setGlobalPrefix`. The prefix belongs to the app whose bootstrap declared
# it; stamping one app's prefix onto the other reports a URL that does not
# exist and loses the one that does.
expected_endpoints = [
  Endpoint.new("/apiv1/alpha/ping", "GET"),
  Endpoint.new("/internal/beta/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/javascript/nestjs_multi_app/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "NestJS analyzer across two applications" do
  it "gives each application its own global prefix" do
    urls = tester.app.endpoints.map(&.url).sort!
    urls.should eq ["/apiv1/alpha/ping", "/internal/beta/ping"]
  end

  it "does not stamp one application's prefix onto the other" do
    tester.app.endpoints.count(&.url.starts_with?("/apiv1/")).should eq 1
    tester.app.endpoints.count(&.url.starts_with?("/internal/")).should eq 1
  end
end
