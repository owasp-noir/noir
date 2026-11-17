require "../../func_spec.cr"

# `spring.mvc.servlet.path` moves everything the DispatcherServlet serves
# below `server.servlet.context-path`: controllers, STOMP endpoints, static
# files and actuator on the main port. Spring Security's filters answer in
# front of the DispatcherServlet, so the login route keeps the context path
# only.
expected_endpoints = [
  Endpoint.new("/shop/app/widgets", "GET"),
  Endpoint.new("/shop/app/stomp", "GET").tap(&.protocol=("ws")),
  Endpoint.new("/shop/app/widget.js", "GET"),
  Endpoint.new("/shop/app/actuator", "GET"),
  Endpoint.new("/shop/app/actuator/health", "GET"),
  Endpoint.new("/shop/signin", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
]

tester = FunctionalTester.new("fixtures/java/spring_servlet_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring spring.mvc.servlet.path", tags: "functional" do
  it "drops the servlet-path-less URLs" do
    urls = tester.endpoints.map(&.url)
    urls.should_not contain("/shop/widgets")
    urls.should_not contain("/shop/stomp")
    urls.should_not contain("/shop/app/signin")
  end
end
