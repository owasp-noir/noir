require "../../func_spec.cr"

# A Pydantic body model imported from a top-level package outside the
# app's own root still expands into its fields (#3545):
#
#   * `sibling/`: `from shared.schemas.refunds import RefundIn`, with the
#     path-dependency package at `shared/shared/`.
#   * `flat/`: `from core.schemas import OrderIn` in
#     `backend/api/routers/orders.py`, the service run from `backend/api`.
#   * `sibling/` also imports `common`, which both `shared/` and `libs/`
#     hold. Both possible definitions of NoteIn declare the text field.
expected_endpoints = [
  Endpoint.new("/orders", "POST", [
    Param.new("customer_email", "", "json"),
    Param.new("amount", "", "json"),
  ]),
  Endpoint.new("/refunds", "POST", [
    Param.new("order_id", "", "json"),
    Param.new("reason", "", "json"),
  ]),
  Endpoint.new("/notes", "POST", [Param.new("text", "", "json")]),
  Endpoint.new("/notes/embedded", "POST", [Param.new("data", "", "json")]),
  Endpoint.new("/notes/pair", "POST", [
    Param.new("first", "", "json"),
    Param.new("second", "", "json"),
  ]),
  Endpoint.new("/notes/external", "POST", [
    Param.new("body", "", "json"),
    Param.new("preview", "false", "query"),
  ]),
  Endpoint.new("/api/v1/orders", "POST", [
    Param.new("customer_email", "", "json"),
    Param.new("amount", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/python/fastapi_package_roots/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "FastAPI package roots: ambiguous package", tags: "functional" do
  it "marks the opaque body and treats a field found in both packages as resolved" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/fastapi_package_roots/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    notes = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/notes" }
    notes.params.map { |param| {param.name, param.param_type} }.should eq([{"text", "json"}])
    notes.params.first.tags.map(&.name).should_not contain("unresolved")

    external = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/notes/external" }
    external.params.find! { |param| param.name == "body" }.tags.map(&.name).should contain("unresolved")
  end
end
