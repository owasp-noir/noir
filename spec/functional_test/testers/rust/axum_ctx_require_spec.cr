require "../../func_spec.cr"

# rust10x/rust-web-app shape (Issue #3265): a workspace whose server crate
# layers a middleware from a lib crate that refuses only through `ctx?`.
describe "Axum ctx-require middleware across workspace crates", tags: "functional" do
  it "guards the route_layer'd route and leaves the controls open" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/rust/axum_ctx_require/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(url : String) do
      endpoint = endpoints.find! { |e| e.method == "POST" && e.url == url }
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("/api/rpc").should eq(["Protected by Rust mw_ctx_require middleware on /rpc"])
    %w[/api/login /api/logoff /api/loose /api/parse /api/logged /api/peek].each do |url|
      guards_of.call(url).should be_empty
    end
  end
end
