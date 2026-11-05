require "../../func_spec.cr"

# Guards that are not a bare role word:
#   * `denyAccessUnlessGranted('@system.show_logs')` (permission strings carry
#     `@` and `.`);
#   * an `access_control` rule that is only an `allow_if` conjunction asking
#     for a login or permission guards; one that can also pass anonymously
#     (`or`) stays undecided.
describe "Symfony permission strings / allow_if access_control", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/symfony_permissions/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads the guards" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    find = ->(url : String) { app.endpoints.find! { |ep| ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }

    guards.call(find.call("/logs")).should eq(["Symfony denyAccessUnlessGranted('@system.show_logs')"])
    guards.call(find.call("/api/info")).size.should eq(1)
    guards.call(find.call("/maybe/info")).should be_empty
    guards.call(find.call("/open/info")).should be_empty
  end
end
