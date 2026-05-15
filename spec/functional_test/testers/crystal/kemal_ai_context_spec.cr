require "../../func_spec.cr"

describe "--ai-context on Kemal auth fixtures" do
  fixture_path = "fixtures/crystal/kemal_auth/"
  app_suffix = "spec/functional_test/fixtures/crystal/kemal_auth/app.cr"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "surfaces Kemal auth guards while leaving public routes clean" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    profile_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/profile" }
    profile_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 4 }.should be_true
    profile_context = profile_endpoint.ai_context
    profile_context = profile_context.should_not be_nil
    profile_context.guards.size.should eq(1)
    profile_context.guards[0].source.should eq("crystal_auth")

    secret_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/secret" }
    secret_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 10 }.should be_true
    secret_context = secret_endpoint.ai_context
    secret_context = secret_context.should_not be_nil
    secret_context.guards.size.should eq(1)
    secret_context.guards[0].source.should eq("crystal_auth")

    health_endpoint = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/health" }
    health_endpoint.details.code_paths.any? { |info| info.path.ends_with?(app_suffix) && info.line == 18 }.should be_true
    health_context = health_endpoint.ai_context
    health_context = health_context.should_not be_nil
    health_context.guards.should be_empty
  end
end
