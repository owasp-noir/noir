require "../../func_spec.cr"

describe "--ai-context Hunt signals on Spring fixtures" do
  fixture_path = "fixtures/java/spring/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps body identifiers from inheriting path-style Hunt IDOR noise" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    create_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/items" }.ai_context
    create_context = create_context.should_not be_nil
    create_context.signals.map(&.kind).should_not contain("idor")
    create_context.signals.map(&.kind).should_not contain("identifier_input")

    client_create_context = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/v2/items" }.ai_context
    client_create_context = client_create_context.should_not be_nil
    client_create_context.signals.map(&.kind).should_not contain("idor")
    client_create_context.signals.map(&.kind).should_not contain("identifier_input")

    update_context = endpoints.find! { |ep| ep.method == "PUT" && ep.url == "/items/update/{id}" }.ai_context
    update_context = update_context.should_not be_nil
    update_context.signals.map(&.kind).should contain("idor")
    update_context.signals.map(&.kind).should_not contain("identifier_input")
  end
end
