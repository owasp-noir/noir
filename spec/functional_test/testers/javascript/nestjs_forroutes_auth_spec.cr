require "../../func_spec.cr"

describe "NestJS forRoutes middleware guards", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards only the method and path forRoutes names" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nestjs_forroutes_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    find = ->(method : String, url : String) { endpoints.find! { |e| e.method == method && e.url == url } }
    guards_of = ->(method : String, url : String) do
      find.call(method, url).ai_context.try(&.guards.map(&.description)) || [] of String
    end
    signals_of = ->(method : String, url : String) do
      find.call(method, url).ai_context.try(&.signals.map(&.kind)) || [] of String
    end

    guards_of.call("POST", "/items").join(" ").should contain("AuthMiddleware")
    signals_of.call("POST", "/items").should_not contain("guard_absence")
    guards_of.call("GET", "/items").should be_empty

    guards_of.call("POST", "/notes").join(" ").should contain("AuthMiddleware")
    guards_of.call("GET", "/notes").should be_empty

    guards_of.call("POST", "/logs").should be_empty
  end
end
