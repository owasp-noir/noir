require "../../func_spec.cr"

# Spring Framework 6 (Boot 3) maps only `@Controller` beans: directly, through
# a project stereotype, or up the type hierarchy. A class whose only marker
# is a type-level `@RequestMapping` serves nothing there, while the Boot 2
# module keeps the Spring 5 behaviour and maps it. An annotation declared
# outside the scan (`@CompanyController`) may be such a stereotype, so its
# class stays.
expected_endpoints = [
  Endpoint.new("/api/gadgets/list", "GET"),
  Endpoint.new("/api/orders/list", "GET"),
  Endpoint.new("/api/payments/list", "GET"),
  Endpoint.new("/api/tools/list", "GET"),
  Endpoint.new("/v1/widgets/list", "GET"),
]

tester = FunctionalTester.new("fixtures/java/spring_boot3_handlers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Spring 6 handler detection", tags: "functional" do
  it "drops a Boot 3 class with no controller stereotype" do
    tester.endpoints.map(&.url).should_not contain("/api/widgets/list")
  end
end
