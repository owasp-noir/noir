require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users/{Id}", "GET", [
    Param.new("Id", "", "path"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("Name", "", "json"),
    Param.new("Email", "", "json"),
  ]),
  Endpoint.new("/search", "GET", [
    Param.new("Keyword", "", "query"),
    Param.new("Page", "", "query"),
    Param.new("TraceId", "", "header"),
  ]),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/legacy/status", "GET"),
  Endpoint.new("/legacy/status", "HEAD"),
  Endpoint.new("/v2/status", "GET"),
  Endpoint.new("/v2/status", "HEAD"),
  Endpoint.new("/users/{Id}", "DELETE", [
    Param.new("Id", "", "path"),
    Param.new("Soft", "", "query"),
  ]),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/uploads", "POST", [
    Param.new("Payload", "", "json"),
    Param.new("SessionId", "", "cookie"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/fastendpoints/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "FastEndpoints analyzer edge cases" do
  it "treats EndpointWithoutRequest<TResponse> as response-only — no DTO leakage" do
    status = tester.app.endpoints.find { |e| e.url == "/status" && e.method == "GET" }
    status.should_not be_nil
    status.as(Endpoint).params.empty?.should be_true
  end

  it "ignores commented-out verb calls inside Configure()" do
    tester.app.endpoints.any? { |e| e.url == "/decoy" }.should be_false
  end
end

describe "FastEndpoints auth tagger" do
  fixture_path = "fixtures/csharp/fastendpoints/"

  it "tags endpoints behind Roles/Permissions and skips AllowAnonymous ones" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    create = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/users" }
    create.tags.any? { |tag| tag.tagger == "fastendpoints_auth" }.should be_true

    upload = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/uploads" }
    upload.tags.any? { |tag| tag.tagger == "fastendpoints_auth" }.should be_true

    ping = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/ping" }
    ping.tags.any? { |tag| tag.tagger == "fastendpoints_auth" }.should be_false
  end
end
