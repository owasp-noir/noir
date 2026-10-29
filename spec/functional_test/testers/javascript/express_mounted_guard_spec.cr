require "../../func_spec.cr"

describe "Express path guards under a router mount", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "applies router.use and router.all guards with the router's mount prefix" do
    {"express_mounted_use_guard" => "use", "express_mounted_all_guard" => "all"}.each do |dir, _kind|
      CodeLocator.instance.clear_all
      options = ConfigInitializer.new.default_options
      options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/#{dir}/")])
      options["ai_context"] = YAML::Any.new(true)
      options["nolog"] = YAML::Any.new(true)

      app = NoirRunner.new(options)
      app.detect
      app.analyze
      endpoints = app.endpoints

      guards_of = ->(method : String, url : String) do
        endpoints.find! { |e| e.method == method && e.url == url }.ai_context.try(&.guards.map(&.description)) || [] of String
      end

      guards_of.call("GET", "/api/apps/installations").join(" ").should contain("requireStaff")
      guards_of.call("DELETE", "/api/apps/installations/:id").join(" ").should contain("requireStaff")
      guards_of.call("GET", "/api/health").should be_empty
    end

    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_mounted_use_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    posts = app.endpoints.find! { |e| e.method == "GET" && e.url == "/api/posts" }
    (posts.ai_context.try(&.guards.map(&.description)) || [] of String).join(" ").should contain("requireStaff")
  end
end
