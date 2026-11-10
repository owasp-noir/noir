require "../../func_spec.cr"

# A Pydantic body model imported from a top-level package outside the
# app's own root still expands into its fields (#3545):
#
#   * `sibling/`: `from shared.schemas.refunds import RefundIn`, with the
#     path-dependency package at `shared/shared/`.
#   * `flat/`: `from core.schemas import OrderIn` in
#     `backend/api/routers/orders.py`, the service run from `backend/api`.
#   * `sibling/` also imports `common`, which both `shared/` and `libs/`
#     hold: ambiguous, so `/notes` reads no model, even though `shared/`
#     is the root picked for `shared`.
expected_endpoints = [
  Endpoint.new("/orders", "POST", [
    Param.new("customer_email", "", "json"),
    Param.new("amount", "", "json"),
  ]),
  Endpoint.new("/refunds", "POST", [
    Param.new("order_id", "", "json"),
    Param.new("reason", "", "json"),
  ]),
  Endpoint.new("/notes", "POST"),
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
  it "binds no model from a package two roots hold" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/fastapi_package_roots/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/notes" }.params.map(&.name).should_not contain("text")
  end
end
