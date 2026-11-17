require "../../func_spec.cr"

# Spring Data REST is served by the DispatcherServlet, so its repositories
# sit under context path + `spring.mvc.servlet.path` + its own base path.
expected_endpoints = [
  Endpoint.new("/shop/app/api/gadgets", "GET"),
  Endpoint.new("/shop/app/api/gadgets", "POST"),
  Endpoint.new("/shop/app/api/gadgets/{id}", "GET"),
  Endpoint.new("/shop/app/api/gadgets/{id}", "PUT"),
  Endpoint.new("/shop/app/api/gadgets/{id}", "PATCH"),
  Endpoint.new("/shop/app/api/gadgets/{id}", "DELETE"),
]

tester = FunctionalTester.new("fixtures/java/spring_data_rest_servlet_path/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring Data REST below spring.mvc.servlet.path", tags: "functional" do
  it "drops the servlet-path-less URLs" do
    tester.endpoints.map(&.url).should_not contain("/shop/api/gadgets")
  end
end
