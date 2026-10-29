require "../../func_spec.cr"

describe "express-jwt aliases and object properties", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards express-jwt behind an import alias or a default-export property" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_jwt_alias_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(url : String) do
      endpoints.find! { |e| e.method == "GET" && e.url == url }.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("/feed").join(" ").should contain("express-jwt")
    guards_of.call("/alias").join(" ").should contain("express-jwt")
    guards_of.call("/optional").should be_empty
    guards_of.call("/optional-alias").should be_empty
    guards_of.call("/open").should be_empty
  end
end
