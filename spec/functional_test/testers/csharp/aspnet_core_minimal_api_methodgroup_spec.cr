require "../../func_spec.cr"

# Method-group handlers (`MapGet("/x", Handler)`), `[AsParameters]` bundle
# expansion and dependency-injected service dropping — the dominant style in
# modern minimal APIs (eShop, vertical-slice / REPR).
list_products = Endpoint.new("/products", "GET", [
  Param.new("page", "", "query"),
  Param.new("sort", "", "query"),
])
list_products.push_callee(Callee.new("repository.Query"))
list_products.push_callee(Callee.new("Results.Ok"))

get_product = Endpoint.new("/products/{id}", "GET", [
  Param.new("id", "", "path"),
])
get_product.push_callee(Callee.new("repository.Find"))

create_product = Endpoint.new("/products", "POST", [
  Param.new("request", "", "json"),
])
create_product.push_callee(Callee.new("repository.Add"))

search = Endpoint.new("/search", "GET", [
  Param.new("Term", "", "query"),
  Param.new("Page", "", "query"),
  Param.new("X-Tenant", "", "header"),
])

inventory = Endpoint.new("/inventory", "GET")
inventory.push_callee(Callee.new("repository.All"))

create_order = Endpoint.new("/orders", "POST", [
  Param.new("x-request-id", "", "header"),
  Param.new("order", "", "json"),
])
create_order.push_callee(Callee.new("sender.Send"))

expected_endpoints = [
  list_products,
  get_product,
  create_product,
  search,
  inventory,
  create_order,
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_methodgroup/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "ASP.NET Core Minimal API method-group analyzer edge cases" do
  it "drops DI services injected into a lambda handler" do
    inv = tester.app.endpoints.find { |e| e.url == "/inventory" && e.method == "GET" }
    inv.should_not be_nil
    inv.as(Endpoint).params.empty?.should be_true
  end

  it "drops the injected service member when expanding [AsParameters]" do
    s = tester.app.endpoints.find { |e| e.url == "/search" && e.method == "GET" }
    s.should_not be_nil
    s.as(Endpoint).params.any? { |p| p.name.downcase == "repository" }.should be_false
  end

  it "does not record binding attributes or route metadata as callees" do
    order = tester.app.endpoints.find { |e| e.url == "/orders" && e.method == "POST" }
    order.should_not be_nil
    names = order.as(Endpoint).callees.map(&.name)
    names.any? { |n| n == "FromHeader" }.should be_false
  end

  it "does not record fluent route-builder metadata as callees" do
    products = tester.app.endpoints.find { |e| e.url == "/products" && e.method == "GET" }
    products.should_not be_nil
    names = products.as(Endpoint).callees.map(&.name)
    names.any? { |n| n == "WithName" || n == "Produces" }.should be_false
  end
end
