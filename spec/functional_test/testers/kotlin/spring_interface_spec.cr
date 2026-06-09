require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("service.show", line: 10))
  end,

  Endpoint.new("/api/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("service.create", line: 14))
  end,
]

FunctionalTester.new("fixtures/kotlin/spring_interface/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "--ai-context on Kotlin Spring interface controller fixtures" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps both the interface declaration and implementation body in endpoint context" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_interface/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/users" }
    endpoint.details.code_paths.any? { |path| path.path.ends_with?("UserApi.kt") && path.line == 14 }.should be_true
    endpoint.details.code_paths.any? { |path| path.path.ends_with?("UserController.kt") && path.line == 7 }.should be_true
    context = endpoint.ai_context
    context = context.should_not be_nil
    context.callees.map(&.name).should contain("service.create")
  end
end
