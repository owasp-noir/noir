require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/v1/pets", "GET"),
  Endpoint.new("/v1/pets", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/v1/pets/search", "GET", [
    Param.new("name", "", "query"),
    Param.new("X-Request-Id", "", "header"),
  ]),
  Endpoint.new("/v1/pets/upload", "POST", [
    Param.new("file", "", "form"),
    Param.new("description", "", "form"),
  ]),
  Endpoint.new("/v1/pets/submit", "POST", [
    Param.new("pet_name", "", "form"),
  ]),
  Endpoint.new("/v1/pets/{petId}", "GET", [Param.new("petId", "", "path")]),
  Endpoint.new("/v1/pets/{petId}", "PUT", [
    Param.new("petId", "", "path"),
    Param.new("name", "", "json"),
    Param.new("breed", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/oas2/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

FunctionalTester.new("fixtures/specification/oas2_security/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/v1/items", "GET", [
    Param.new("X-API-Key", "", "header"),
  ]),
  Endpoint.new("/v1/items", "POST", [
    Param.new("name", "", "json"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/v1/public", "GET"),
  Endpoint.new("/v1/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("api_key", "", "query"),
  ]),
]).perform_tests

FunctionalTester.new("fixtures/specification/oas2_edge_cases/", {
  :techs     => 1,
  :endpoints => 3,
}, [
  Endpoint.new("/api/orders", "GET", [
    Param.new("X-Tenant", "", "header"),
    Param.new("state", "", "query"),
  ]),
  Endpoint.new("/api/orders", "POST", [
    Param.new("X-Tenant", "", "header"),
    Param.new("name", "", "json"),
    Param.new("expedited", "", "json"),
    Param.new("gift_message", "", "json"),
  ]),
  Endpoint.new("/api/uploads", "POST", [
    Param.new("file", "", "form"),
    Param.new("description", "", "form"),
  ]),
]).perform_tests

# `readOnly: true` marks a property as response-only (Swagger 2.0), so it is
# not a request param: not in JSON or form bodies, not inline or behind a
# `$ref`, not in YAML or JSON documents. `readOnly: false` and a non-boolean
# `readOnly` keep the property.
read_only_endpoints = [] of Endpoint
{"yaml", "json"}.each do |fmt|
  read_only_endpoints << Endpoint.new("/#{fmt}/pets", "POST", [
    Param.new("status", "", "json"),
    Param.new("name", "", "json"),
    Param.new("note", "", "json"),
  ])
  read_only_endpoints << Endpoint.new("/#{fmt}/pets/form", "POST", [Param.new("nickname", "", "form")])
  read_only_endpoints << Endpoint.new("/#{fmt}/pets/ref", "PUT", [Param.new("breed", "", "json")])
end

read_only_tester = FunctionalTester.new("fixtures/specification/oas2_read_only/", {
  :techs     => 1,
  :endpoints => read_only_endpoints.size,
}, read_only_endpoints)
read_only_tester.perform_tests

describe "OAS2 readOnly request properties", tags: "functional" do
  it "drops properties marked readOnly: true" do
    names = ->(url : String) { read_only_tester.endpoints.find!(&.url.==(url)).params.map(&.name) }
    {"yaml", "json"}.each do |fmt|
      names.call("/#{fmt}/pets").should_not contain "id"
      names.call("/#{fmt}/pets/form").should_not contain "created_at"
      names.call("/#{fmt}/pets/ref").should_not contain "uid"
    end
  end
end
