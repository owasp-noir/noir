require "../../func_spec.cr"

# A Ktor `sessions.get` is a guard only when a missing session refuses or
# redirects. An optional read that still renders the page is not (#3296).
describe "Ktor optional session reads", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards a missing session that is refused and not one that renders" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/ktor_session_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards = ->(url : String) do
      endpoint = endpoints.find { |item| item.method == "GET" && item.url == url }
      fail("missing GET #{url}; have #{endpoints.map { |item| "#{item.method} #{item.url}" }}") unless endpoint
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards.call("/login").should be_empty
    guards.call("/secret").should eq(["Protected by Ktor session check"])
  end
end
