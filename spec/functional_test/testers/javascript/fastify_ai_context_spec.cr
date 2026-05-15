require "../../func_spec.cr"

describe "--ai-context on Fastify auth fixtures" do
  fixture_path = "fixtures/javascript/fastify_auth/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps auth detections on protected routes only" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints
    endpoints.size.should eq(5)

    secure_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/secure" }.ai_context
    secure_context = secure_context.should_not be_nil
    secure_context.guards.size.should eq(1)
    secure_context.guards[0].source.should eq("js_misc_auth")

    public_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/public/health" }.ai_context
    public_context = public_context.should_not be_nil
    public_context.guards.should be_empty
  end
end
