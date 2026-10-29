require "../../func_spec.cr"

# `can:` is the alias of Laravel's `Authorize` middleware (#3300): an
# authorization guard, on a group or on the route itself.
describe "Laravel can: middleware", tags: "functional" do
  it "tags `can:` middleware as authorization" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/laravel_can_middleware/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    authz = ->(url : String) do
      ep = app.endpoints.find! { |endpoint| endpoint.method == "DELETE" && endpoint.url == url }
      ep.tags.select(&.name.==("authz")).map(&.description)
    end
    authz.call("/settings/users/{user}").should eq(["Protected by Laravel can:administrator middleware"])
    authz.call("/users/{user}").should eq(["Protected by Laravel can:delete,user middleware"])
  ensure
    CodeLocator.instance.clear_all
  end
end
