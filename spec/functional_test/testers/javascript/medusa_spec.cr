require "../../func_spec.cr"

describe "Medusa v2 file routes and authenticate matchers", tags: "functional" do
  it "reads src/api route.ts verbs, params, and authenticate matchers" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/medusa/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    CodeLocator.instance.clear_all
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.techs.sort.should eq ["js_medusa"]

    endpoints = app.endpoints
    find = ->(method : String, url : String) { endpoints.find! { |endpoint| endpoint.method == method && endpoint.url == url } }
    params_of = ->(method : String, url : String) { find.call(method, url).params.map { |param| {param.name, param.param_type} } }
    guards_of = ->(method : String, url : String) do
      context = find.call(method, url).ai_context
      return [] of String unless context

      context.guards.select { |guard| guard.kind == "auth_guard" }.map(&.description.not_nil!)
    end

    endpoints.map { |endpoint| {endpoint.method, endpoint.url} }.sort!.should eq([
      {"GET", "/store/hello/{id}"},
      {"POST", "/admin/custom"},
    ])
    params_of.call("GET", "/store/hello/{id}").should eq([{"id", "path"}, {"q", "query"}])
    params_of.call("POST", "/admin/custom").should eq([{"name", "json"}])
    guards_of.call("POST", "/admin/custom").should eq(["Protected by authenticate(\"user\", [\"session\", \"bearer\"])"])
    guards_of.call("GET", "/store/hello/{id}").should be_empty
  end
end
