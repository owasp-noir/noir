require "../../func_spec.cr"

describe "Axum inherent status_code impls", tags: "functional" do
  it "guards an extractor whose Rejection status_code is an inherent impl" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/rust/axum_inherent_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(method : String, url : String) do
      endpoint = endpoints.find! { |e| e.method == method && e.url == url }
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("POST", "/items").should eq(["Protected by Rust AuthUser request guard"])
    guards_of.call("POST", "/missing").should be_empty
    guards_of.call("POST", "/admin").should eq(["Protected by Rust AdminUser request guard"])
  end
end
