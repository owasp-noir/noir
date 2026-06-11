require "../../func_spec.cr"

# Regression test for --include-callee on FastAPI. Exercises four
# distinct emit paths:
#
#   1. POST /users          — straight @app.post with bare-identifier
#                              callees (save_user, audit_log).
#   2. GET /healthz         — no calls in the body; confirms empty
#                              callees stay empty.
#   3. GET /profile         — stacked decorators (@app.get +
#                              @auth_required + @rate_limit(10)). The
#                              pre-fix code assumed def was at
#                              `index + 1` and silently emitted zero
#                              callees here.
#   4. DELETE /orders/{...} — blank line + comment between the route
#                              decorator and the def. Same fragility,
#                              same fix path.
#   5. GET /internal/reports — @api.get on an APIRouter declared in
#                              a separate file; locks in that the
#                              include_router emit branch also pushes
#                              callees.
db_path = "./spec/functional_test/fixtures/python/fastapi_callees/db.py"
main_path = "./spec/functional_test/fixtures/python/fastapi_callees/main.py"

expected_endpoints = [
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "query"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/healthz", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_status", main_path, 16))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/orders/{order_id}", "DELETE").tap do |ep|
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  Endpoint.new("/internal/reports", "GET").tap do |ep|
    ep.push_callee(Callee.new("db.fetch_report", db_path, 9))
  end,

  # 6. GET /exports/{file_path:path} — programmatic route registration
  #    with a FastAPI typed path converter. The converter should not
  #    make `file_path` appear as both query and path, and the handler
  #    reference should seed callee/AI-context output even before its
  #    body callees are resolved.
  Endpoint.new("/exports/{file_path}", "GET").tap do |ep|
    ep.push_param(Param.new("file_path", "", "path"))
    ep.push_callee(Callee.new("export_file", main_path, 31))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  # 7. GET /reports — multi-line typed signature (`) -> dict:` at
  #    column 0). The handler body (and its callees) used to be
  #    dropped because parse_code_block treated the signature closer
  #    as the end of the block.
  Endpoint.new("/reports", "GET").tap do |ep|
    ep.push_callee(Callee.new("save_user", db_path, 1))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,

  # 8. GET /decorated — multi-line route decorator with a Depends()
  #    call before the handler. The decorator continuation must not be
  #    treated as the handler def; otherwise `limit` is missed and
  #    Depends is emitted as a handler callee.
  Endpoint.new("/decorated", "GET").tap do |ep|
    ep.push_param(Param.new("limit", "10", "query"))
    ep.push_callee(Callee.new("audit_log", db_path, 5))
  end,
]

FunctionalTester.new("fixtures/python/fastapi_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "FastAPI programmatic route callees" do
  it "does not emit handler references unless callee context is requested" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/fastapi_callees/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/exports/{file_path}" }
    endpoint.callees.should be_empty
    endpoint.params.select { |param| param.name == "file_path" }.map(&.param_type).should eq(["path"])
  end
end

describe "FastAPI multi-line decorator callee scope" do
  it "does not treat decorator dependency calls as handler callees" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/fastapi_callees/")])
    options["nolog"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/decorated" }
    endpoint.params.any? { |param| param.name == "limit" && param.param_type == "query" }.should be_true
    endpoint.callees.map(&.name).should_not contain("Depends")
  end
end
