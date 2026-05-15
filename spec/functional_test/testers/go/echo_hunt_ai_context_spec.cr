require "../../func_spec.cr"

describe "--ai-context Hunt signals on Echo fixtures" do
  fixture_path = "fixtures/go/echo/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "drops redundant generic param signals when Hunt already provides a stronger label" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    pet_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/pet" }.ai_context
    pet_context = pet_context.should_not be_nil
    pet_context.signals.map(&.kind).should_not contain("sqli")
    pet_context.signals.map(&.kind).should_not contain("query_builder_input")

    review_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/items/:itemId/reviews" }.ai_context
    review_context = review_context.should_not be_nil
    review_context.signals.map(&.kind).should contain("sqli")
    review_context.signals.map(&.kind).should_not contain("query_builder_input")

    patch_context = endpoints.find! { |ep| ep.method == "PATCH" && ep.url == "/users/:id" }.ai_context
    patch_context = patch_context.should_not be_nil
    patch_context.signals.map(&.kind).should contain("path_param")
    patch_context.signals.map(&.kind).should contain("idor")
    patch_context.signals.map(&.kind).should contain("idor_review")
    patch_context.signals.map(&.kind).should_not contain("identifier_input")
    patch_context.signals.map(&.kind).should_not contain("guard_absence")

    cache_context = endpoints.find! { |ep| ep.method == "DELETE" && ep.url == "/v2/admin/cache" }.ai_context
    cache_context = cache_context.should_not be_nil
    cache_context.signals.map(&.kind).should contain("guard_absence")
    cache_context.signals.map(&.kind).should_not contain("idor_review")
  end
end
