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

# A body DTO is the members a client sends, camelCased as ASP.NET Core
# writes JSON, not one field named after the argument.
create_product = Endpoint.new("/products", "POST", [
  Param.new("name", "", "json"),
  Param.new("price", "", "json"),
])
create_product.push_callee(Callee.new("repository.Add"))

search = Endpoint.new("/search", "GET", [
  Param.new("Term", "", "query"),
  Param.new("Page", "", "query"),
  Param.new("X-Tenant", "", "header"),
])

search_inline = Endpoint.new("/search-inline", "GET", [
  Param.new("Term", "", "query"),
  Param.new("Page", "", "query"),
  Param.new("X-Tenant", "", "header"),
])

upload = Endpoint.new("/upload", "POST", [
  Param.new("file", "", "form"),
  Param.new("title", "", "form"),
])

inventory = Endpoint.new("/inventory", "GET")
inventory.push_callee(Callee.new("repository.All"))

create_order = Endpoint.new("/orders", "POST", [
  Param.new("x-request-id", "", "header"),
  Param.new("sku", "", "json"),
  Param.new("quantity", "", "json"),
])

# A DTO declared in another file honours `[JsonPropertyName]` and drops a
# `[JsonIgnore]` member; a header named by a `const string` resolves.
hooks = Endpoint.new("/hooks", "POST", [
  Param.new("X-Hook-Token", "", "header"),
  Param.new("url", "", "json"),
  Param.new("grant_url", "", "json"),
])
create_order.push_callee(Callee.new("sender.Send"))

expected_endpoints = [
  list_products,
  get_product,
  create_product,
  search,
  search_inline,
  upload,
  inventory,
  create_order,
  hooks,
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_minimal_api_methodgroup/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "ASP.NET Core Minimal API method-group analyzer edge cases", tags: "functional" do
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

  it "expands [AsParameters] on an inline lambda instead of reporting the bundle" do
    s = tester.app.endpoints.find { |e| e.url == "/search-inline" && e.method == "GET" }
    s.should_not be_nil
    s.as(Endpoint).params.any? { |p| p.name == "query" || p.name.downcase == "repository" }.should be_false
  end

  it "does not report an uploaded file as a JSON body" do
    u = tester.app.endpoints.find { |e| e.url == "/upload" && e.method == "POST" }
    u.should_not be_nil
    u.as(Endpoint).params.any? { |p| p.name == "file" && p.param_type == "json" }.should be_false
  end

  it "does not record binding attributes or route metadata as callees" do
    order = tester.app.endpoints.find { |e| e.url == "/orders" && e.method == "POST" }
    order.should_not be_nil
    names = order.as(Endpoint).callees.map(&.name)
    names.any? { |n| n == "FromHeader" }.should be_false
  end

  it "names the handler at its definition: a method group's declaration, a lambda's first line" do
    handler = ->(url : String, method : String) { tester.app.endpoints.find! { |e| e.url == url && e.method == method }.handler }
    handler.call("/products", "GET").try { |h| {h.name, h.line} }.should eq({"GetProducts", 49})
    handler.call("/products/{id}", "GET").try { |h| {h.name, h.line} }.should eq({"GetProductById", 55})
    handler.call("/orders", "POST").try { |h| {h.name, h.line} }.should eq({"closure", 34})
    handler.call("/hooks", "POST").try(&.path).to_s.should end_with("Program.cs")
  end

  it "drops a [JsonIgnore] body member" do
    hooks = tester.app.endpoints.find! { |e| e.url == "/hooks" && e.method == "POST" }
    hooks.params.any? { |p| p.name.downcase == "secret" || p.name == "hook" }.should be_false
  end

  it "does not record fluent route-builder metadata as callees" do
    products = tester.app.endpoints.find { |e| e.url == "/products" && e.method == "GET" }
    products.should_not be_nil
    names = products.as(Endpoint).callees.map(&.name)
    names.any? { |n| n == "WithName" || n == "Produces" }.should be_false
  end
end
