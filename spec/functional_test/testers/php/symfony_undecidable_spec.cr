require "../../func_spec.cr"

# An access_control rule or firewall that cannot be decided statically
# (`or`, `host`) only leaves the paths it covers undecided; it must not hide
# the guards of the rules and firewalls after it.
describe "Symfony undecidable access_control scope", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/symfony_undecidable/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "keeps later guards for paths the undecidable entry does not cover" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    find = ->(url : String) { app.endpoints.find! { |ep| ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }

    guards.call(find.call("/other/x")).should eq(["Symfony access_control (ROLE_USER)"])
    guards.call(find.call("/a1/x")).should be_empty
    guards.call(find.call("/host/x")).should be_empty
    guards.call(find.call("/api/x")).should be_empty
    # The POST-only undecidable rule does not cover GET.
    guards.call(find.call("/m/x")).should eq(["Symfony access_control (ROLE_USER)"])
  end
end
