require "../../func_spec.cr"

describe "--ai-context on Mux fixtures" do
  fixture_path = "fixtures/go/mux/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "classifies FormValue inputs according to the route method" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    submit_endpoint = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/submit" }
    submit_endpoint.params.map { |param| {param.name, param.param_type} }.should contain({"password", "form"})
    submit_context = submit_endpoint.ai_context
    submit_context = submit_context.should_not be_nil
    submit_context.signals.map(&.name).should contain("form.password")
    submit_context.signals.map(&.name).should_not contain("query.password")

    patch_endpoint = endpoints.find! { |ep| ep.method == "PATCH" && ep.url == "/items/{id}/status" }
    patch_endpoint.params.map { |param| {param.name, param.param_type} }.should contain({"status", "form"})
    patch_context = patch_endpoint.ai_context
    patch_context = patch_context.should_not be_nil
    patch_context.signals.map(&.kind).should contain("idor_review")
  end
end
