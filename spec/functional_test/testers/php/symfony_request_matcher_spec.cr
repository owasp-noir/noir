require "../../func_spec.cr"

# Symfony ignores a firewall's `pattern:` when it has a `request_matcher:`, so
# that firewall may handle any path: the access_control result is undecided.
describe "Symfony firewall with request_matcher", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/symfony_request_matcher/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "leaves paths undecided" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    ep = app.endpoints.find! { |e| e.url == "/foo" }
    (ep.ai_context.try(&.guards.map(&.name)) || [] of String).should be_empty
  end
end
