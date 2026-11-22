require "../../func_spec.cr"

# Spring Data REST is served by the DispatcherServlet, so its repositories
# sit under context path + `spring.mvc.servlet.path` + its own base path.
gadget_body = [Param.new("id", "", "json"), Param.new("sku", "", "json")]
expected_endpoints = [
  Endpoint.new("/shop/app/api/gadgets", "GET", [
    Param.new("page", "", "query"),
    Param.new("size", "", "query"),
    Param.new("sort", "", "query"),
  ]),
  Endpoint.new("/shop/app/api/gadgets", "POST", gadget_body),
  Endpoint.new("/shop/app/api/gadgets/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/shop/app/api/gadgets/{id}", "PUT", gadget_body + [Param.new("id", "", "path")]),
  Endpoint.new("/shop/app/api/gadgets/{id}", "PATCH", gadget_body + [Param.new("id", "", "path")]),
  Endpoint.new("/shop/app/api/gadgets/{id}", "DELETE", [Param.new("id", "", "path")]),
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
