require "../../func_spec.cr"

describe "--ai-context Hunt signals on Chi fixtures" do
  fixture_path = "fixtures/go/chi/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps sort-like signals while dropping broad analytics filter false positives" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{fixture_path}")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints

    analytics_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/analytics" }.ai_context
    analytics_context = analytics_context.should_not be_nil
    analytics_context.signals.map(&.kind).should_not contain("sqli")
    analytics_context.sinks.map(&.kind).should_not contain("sql")

    search_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/search-test" }.ai_context
    search_context = search_context.should_not be_nil
    search_context.signals.map(&.kind).should_not contain("sqli")
    search_context.sinks.map(&.kind).should_not contain("sql")

    api_context = endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api-test" }.ai_context
    api_context = api_context.should_not be_nil
    api_context.signals.map(&.name).should_not contain("header.User-Agent")
  end
end
