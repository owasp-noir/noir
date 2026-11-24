require "../../func_spec.cr"

describe "Nextcloud access requirements", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reads what each non-public action asks of the caller" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/nextcloud/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    requires = ->(method : String, url : String) do
      Access.of(app.endpoints.find! { |e| e.method == method && e.url == url }).map(&.to_s)
    end

    requires.call("GET", "/apps/notes/notes").should eq(["authenticated"])
    requires.call("PUT", "/apps/notes/notes/{id}").should eq(["authenticated"])
    # No `NoAdminRequired`: Nextcloud serves it to admins only.
    requires.call("DELETE", "/apps/notes/notes/{id}").should eq(["authenticated", "unresolved"])
    requires.call("POST", "/apps/notes/settings").should eq(["authenticated", "unresolved"])
    # `PublicPage` is no guard.
    requires.call("POST", "/ocs/v2.php/apps/notes/api/v1/share").should be_empty
  end
end
