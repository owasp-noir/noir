require "../../func_spec.cr"

users_index = Endpoint.new("/api/users", "GET", [
  Param.new("page", "", "query"),
  Param.new("limit", "", "query"),
  Param.new("search", "", "query"),
  Param.new("X-API-Key", "", "header"),
  Param.new("session_id", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->query->get", line: 17))
  ep.push_callee(Callee.new("$request->get", line: 19))
  ep.push_callee(Callee.new("$request->headers->get", line: 20))
  ep.push_callee(Callee.new("$request->cookies->get", line: 21))
  ep.push_callee(Callee.new("$this->json", line: 23))
end

users_create = Endpoint.new("/api/users", "POST", [
  Param.new("name", "", "form"),
  Param.new("email", "", "form"),
  Param.new("Authorization", "", "header"),
  Param.new("avatar", "", "file"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->request->get", line: 39))
  ep.push_callee(Callee.new("$request->headers->get", line: 41))
  ep.push_callee(Callee.new("$request->files->get", line: 42))
  ep.push_callee(Callee.new("$this->json", line: 43))
end

users_update = Endpoint.new("/api/users/{id}", "PUT", [
  Param.new("id", "", "path"),
  Param.new("Content-Type", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->getContent", line: 51))
  ep.push_callee(Callee.new("json_decode", line: 51))
  ep.push_callee(Callee.new("$request->headers->get", line: 52))
  ep.push_callee(Callee.new("$this->json", line: 53))
end

products_create = Endpoint.new("/api/products", "POST", [
  Param.new("name", "", "form"),
  Param.new("price", "", "form"),
  Param.new("category", "", "query"),
  Param.new("User-Agent", "", "header"),
  Param.new("image", "", "file"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->request->get", line: 27))
  ep.push_callee(Callee.new("$request->get", line: 29))
  ep.push_callee(Callee.new("$request->headers->get", line: 30))
  ep.push_callee(Callee.new("$request->files->get", line: 31))
  ep.push_callee(Callee.new("$this->json", line: 32))
end

products_update = Endpoint.new("/api/products/{slug}", "PATCH", [
  Param.new("slug", "", "path"),
  Param.new("X-CSRF-Token", "", "header"),
  Param.new("preferences", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->getContent", line: 38))
  ep.push_callee(Callee.new("$request->headers->get", line: 39))
  ep.push_callee(Callee.new("$request->cookies->get", line: 40))
  ep.push_callee(Callee.new("$this->json", line: 41))
end

admin_stats = Endpoint.new("/api/admin/stats", "GET").tap do |ep|
  ep.push_callee(Callee.new("$this->json", line: 15))
end

admin_report = Endpoint.new("/api/admin/reports/{id}", "POST", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("$this->json", line: 23))
end

expected_endpoints = [
  users_index,
  users_create,
  users_update,
  products_create,
  products_update,
  admin_stats,
  admin_report,
]

FunctionalTester.new("fixtures/php/symfony/", {
  :techs     => 2,
  :endpoints => 25, # +4 from StorefrontController multi-line routes (no callees)
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "Symfony YAML route callees" do
  it "keeps YAML-only routes callee-empty" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/symfony/")])
    noir_options["nolog"] = YAML::Any.new(true)
    noir_options["include_callee"] = YAML::Any.new(true)

    app = NoirRunner.new noir_options
    app.detect
    app.analyze

    endpoint = app.endpoints.find { |e| e.method == "GET" && e.url == "/api/health" }
    endpoint.should_not be_nil
    endpoint.callees.should be_empty if endpoint
  end
end
