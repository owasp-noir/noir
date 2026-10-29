require "../../func_spec.cr"

describe "Next.js auth wrapper higher-order functions", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "judges a session wrapper by its definition and leaves a pass-through open" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs_wrapper_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(url : String) do
      endpoints.find! { |e| e.method == "GET" && e.url == url }.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("/api/items").join(" ").should contain("withSession")
    guards_of.call("/api/workspace").join(" ").should contain("withWorkspace")
    guards_of.call("/api/control").join(" ").should contain("401")
    guards_of.call("/api/open").should be_empty
  end
end
