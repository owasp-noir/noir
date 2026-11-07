require "../../func_spec.cr"

# `c.ShouldBind(&req)` on a struct with only `form` tags used to also emit
# json params named after the exported fields (`Name`, `Description`).
# Form-only tags are form params named by the tag. Json is still emitted
# when a `json` tag exists, and an untagged field still binds by its own
# name. `ShouldBindJSON` / `ShouldBindQuery` keep their previous params.
expected_endpoints = [
  Endpoint.new("/tags", "POST", [
    Param.new("name", "", "form"),
    Param.new("description", "", "form"),
  ]),
  Endpoint.new("/tags", "GET", [
    Param.new("name", "", "query"),
    Param.new("description", "", "query"),
  ]),
  Endpoint.new("/orders", "POST", [
    Param.new("first_name", "", "json"),
    Param.new("first_name", "", "form"),
    Param.new("Note", "", "json"),
    Param.new("Note", "", "form"),
  ]),
  Endpoint.new("/messages", "POST", [
    Param.new("title", "", "json"),
    Param.new("Body", "", "json"),
  ]),
  Endpoint.new("/items", "GET", [
    Param.new("limit", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/go/gin_shouldbind_form/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "gin ShouldBind form tags", tags: "functional" do
  it "does not invent json params for form-only tags" do
    created = tester.app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/tags" }
    created.params.map { |p| {p.name, p.param_type} }.should eq([
      {"name", "form"},
      {"description", "form"},
    ])
    listed = tester.app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/tags" }
    listed.params.map { |p| {p.name, p.param_type} }.should eq([
      {"name", "query"},
      {"description", "query"},
    ])
  end
end
