require "../../func_spec.cr"

# Armeria `Server.builder()` routes carry the line of their own registration,
# so `java_misc_auth` can read the decorators around them (#3268). A
# decorator guards the route it is passed to, or the routes under its
# `decoratorUnder` prefix, not the neighbouring registrations.
describe "Armeria builder routes and auth decorators", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags only the routes an AuthService decorator covers" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/armeria_auth/")])
    options["all_taggers"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    by_url = app.endpoints.to_h { |ep| {ep.url, ep} }
    {"/welcome" => 13, "/inline" => 14, "/other" => 15, "/admin/users" => 16}.each do |url, line|
      by_url[url].details.code_paths.first.line.should eq(line)
    end

    auth = ->(url : String) { by_url[url].tags.select { |tag| tag.name == "auth" }.map(&.description) }
    auth.call("/welcome").should be_empty
    auth.call("/other").should be_empty
    auth.call("/inline").should eq(["Protected by Armeria AuthService decorator"])
    auth.call("/admin/users").should eq(["Protected by Armeria AuthService decorator"])
  end
end
