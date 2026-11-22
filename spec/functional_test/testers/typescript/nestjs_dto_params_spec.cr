require "../../func_spec.cr"

# A whole-object `@Body()` / `@Query()` typed with a DTO reports the DTO's
# fields: imported through a barrel, inherited from a generic base or a
# `PickType`, an inline object type, or an interface in another package.
# Methods, accessors, function-valued, static and private members are not
# fields, nor is the next line of a wrapped type (`kind:\n ItemKind;`). A
# same-named class the controller does not import (src/other) is not read;
# a type with no declaration (`Record<...>`) stays one generic param.
expected_endpoints = [
  Endpoint.new("/items", "POST", [Param.new("name", "", "body"), Param.new("tags", "", "body"), Param.new("refs", "", "body"), Param.new("kind", "", "body")]),
  Endpoint.new("/items", "GET", [Param.new("search", "", "query"), Param.new("after", "", "query"), Param.new("limit", "", "query"), Param.new("orderBy", "", "query")]),
  Endpoint.new("/items/:id", "PATCH", [Param.new("id", "", "path"), Param.new("name", "", "body")]),
  Endpoint.new("/items/:id/actions", "POST", [Param.new("id", "", "path"), Param.new("payload", "", "body"), Param.new("status", "", "body")]),
  Endpoint.new("/items/shared", "GET", [Param.new("region", "", "query"), Param.new("owner", "", "query")]),
  Endpoint.new("/items/edit", "PATCH", [
    Param.new("name", "", "body"), Param.new("revision", "", "body"), Param.new("reason", "", "body"),
    Param.new("context", "", "body"), Param.new("if-match", "", "header"),
  ]),
  Endpoint.new("/items/scope/:id/*rest", "GET", [Param.new("id", "", "path"), Param.new("rest", "", "path"), Param.new("if-none-match", "", "header")]),
  Endpoint.new("/items/attributes", "POST", [Param.new("body", "", "body")]),
  Endpoint.new("/items/mixed", "POST", [Param.new("name", "", "body"), Param.new("body", "", "body")]),
  Endpoint.new("/items/union", "POST", [Param.new("body", "", "body")]),
  Endpoint.new("/items/raw", "POST", [Param.new("body", "", "body")]),
]

FunctionalTester.new("fixtures/typescript/nestjs_dto_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "ts_nestjs DTO params", tags: "functional" do
  it "reports exactly the DTO's public fields" do
    tester = FunctionalTester.new("fixtures/typescript/nestjs_dto_params/", {:techs => 1}, [] of Endpoint)
    create = tester.endpoints.find! { |ep| ep.url == "/items" && ep.method == "POST" }
    create.params.map(&.name).sort!.should eq(["kind", "name", "refs", "tags"])
  end

  it "marks the opaque body when its DTO cannot be resolved" do
    tester = FunctionalTester.new("fixtures/typescript/nestjs_dto_params/", {:techs => 1}, [] of Endpoint)
    mixed = tester.endpoints.find! { |ep| ep.url == "/items/mixed" }
    mixed.params.find! { |param| param.name == "body" }.tags.map(&.name).should contain("unresolved")
  end
end
