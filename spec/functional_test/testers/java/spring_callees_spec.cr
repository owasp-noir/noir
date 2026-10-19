require "../../func_spec.cr"

# Regression test for --include-callee on Spring (#1366). Spring is
# the first JVM analyzer to grow callees, and the shape mirrors the
# Python/Go path: a tree-sitter parse already produced for route and
# parameter extraction is reused to walk the matching
# `method_declaration` body for 1-hop `method_invocation` nodes.
#
# Cross-file definition resolution (e.g. `service.save` →
# `UserServiceImpl.save`) is intentionally out of scope for this
# first cut; `Callee#path` therefore points at the call site, matching
# the honest scope on every other analyzer.
#
# Coverage:
#   - POST /api/users/        — bare static (`AuditLog.write`) and
#                               selector-on-identifier
#                               (`service.save`) receivers.
#   - GET  /api/users/profile — `this.foo` receiver shape; the
#                               unambiguous same-file
#                               `buildProfile` declaration resolves
#                               to its definition line, while
#                               `AuditLog.write` (qualified
#                               non-`this`) stays at the call site.
#   - GET  /api/orders/legacy — chained-on-call (`getLegacy().toString()`)
#                               drops the outer `toString` and keeps
#                               only the inner `getLegacy`, matching
#                               the Python/Go chained-call noise filter.
#   - GET  /api/catalog/{id}  — route declared on a springdoc-style
#                               `*Api` interface; callees are pulled
#                               from the `@Override` body on the
#                               concrete controller, not the empty
#                               interface method.
expected_endpoints = [
  Endpoint.new("/api/users/", "POST").tap do |ep|
    ep.push_callee(Callee.new("service.save", line: 20))
    ep.push_callee(Callee.new("AuditLog.write", line: 21))
  end,

  Endpoint.new("/api/users/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("this.buildProfile", line: 32))
    ep.push_callee(Callee.new("AuditLog.write", line: 28))
  end,

  Endpoint.new("/api/orders/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("AuditLog.write", line: 13))
    ep.push_callee(Callee.new("getLegacy", line: 17))
  end,

  Endpoint.new("/api/catalog/{id}", "GET", [Param.new("id", "", "path")]).tap do |ep|
    ep.push_callee(Callee.new("catalogService.load", line: 9))
    ep.push_callee(Callee.new("AuditLog.write", line: 10))
  end,

  # `@ModelAttribute findUser` runs before every handler of UserController,
  # so its `service.load` belongs to this route too (spring-petclinic's
  # `findOwner` → `owners.findById` is the object lookup an IDOR review
  # needs on every owner route).
  Endpoint.new("/api/users/legacy", "GET").tap do |ep|
    ep.push_callee(Callee.new("service.load", line: 39))
  end,

  # `default` interface method no controller overrides.
  Endpoint.new("/api/catalog/ping", "GET"),

  # `@InitBinder` disallows `id` / `*.id`; the `@ControllerAdvice`
  # disallows `secret` for every controller.
  Endpoint.new("/binder/pets", "POST", [
    Param.new("name", "", "form"),
    Param.new("owner.city", "", "form"),
  ]),
  Endpoint.new("/binder/lookup", "GET", [Param.new("id", "", "query")]),
]

tester = FunctionalTester.new("fixtures/java/spring_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

describe "Spring annotation handlers", tags: "functional" do
  # `details.code_paths` stays on the annotation line; the handler is the
  # method the annotation stack decorates, at its own signature line.
  it "names the decorated method at its signature line" do
    legacy = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users/legacy" }
    legacy.details.code_paths.first.line.should eq(43)
    legacy.handler.should eq(Handler.new("UserController.legacy", legacy.details.code_paths.first.path, 44))
  end

  it "names the @Override, not the interface method, for an interface-declared route" do
    item = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/catalog/{id}" }
    item.details.code_paths.first.path.should end_with("CatalogApi.java")
    handler = item.handler.should_not be_nil
    handler.name.should eq("CatalogApiController.getItem")
    handler.path.to_s.should end_with("CatalogApiController.java")
    handler.line.should eq(8)

    ping = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/catalog/ping" }
    ping.handler.should be_nil
  end

  it "drops the bound fields an @InitBinder disallows, but not an explicit @RequestParam" do
    pets = tester.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/binder/pets" }
    pets.params.map(&.name).should_not contain("id")
    pets.params.map(&.name).should_not contain("owner.id")
    pets.params.map(&.name).should_not contain("secret")
    lookup = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/binder/lookup" }
    lookup.params.map(&.name).should eq(["id"])
  end

  it "attributes @ModelAttribute callees to every route of the controller" do
    create = tester.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users/" }
    create.callees.map(&.name).should contain("service.load")
    legacy_order = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/orders/legacy" }
    legacy_order.callees.map(&.name).should_not contain("service.load")
  end
end
