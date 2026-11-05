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

    note = Analyzer::Php::SymfonySecurity::VOTER_NOTE
    guards.call(find.call("/logs")).should eq(["Symfony denyAccessUnlessGranted('@system.show_logs')#{note}"])
    guards.call(find.call("/rolecheck")).should eq(["Symfony denyAccessUnlessGranted('ROLE_ADMIN')"])
    guards.call(find.call("/dyn")).should be_empty
    guards.call(find.call("/dyncheck")).should be_empty
    guards.call(find.call("/voted")).should eq(["Symfony #[IsGranted('@parts.read')]#{note}"])
    guards.call(find.call("/cmp/x")).should be_empty
    guards.call(find.call("/str/x")).should be_empty
    guards.call(find.call("/role/x")).size.should eq(1)
    guards.call(find.call("/role/x")).first.should_not contain("voter")
    guards.call(find.call("/api/info")).should eq(["Symfony access_control (allow_if: is_granted(\"@api.access\") and is_authenticated()#{note})"])
    guards.call(find.call("/maybe/info")).should be_empty
    guards.call(find.call("/open/info")).should be_empty
  end
end
