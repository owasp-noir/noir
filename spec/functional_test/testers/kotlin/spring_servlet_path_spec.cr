require "../../func_spec.cr"

# `spring.mvc.servlet.path` (trailing slash and all) prefixes the
# DispatcherServlet's controller routes and STOMP endpoints.
expected_endpoints = [
  Endpoint.new("/app/gadgets", "GET"),
  Endpoint.new("/app/stomp", "GET").tap(&.protocol=("ws")),
]

tester = FunctionalTester.new("fixtures/kotlin/spring_servlet_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Kotlin Spring spring.mvc.servlet.path", tags: "functional" do
  it "drops the servlet-path-less URLs" do
    urls = tester.endpoints.map(&.url)
    urls.should_not contain("/gadgets")
    urls.should_not contain("/stomp")
  end
end
