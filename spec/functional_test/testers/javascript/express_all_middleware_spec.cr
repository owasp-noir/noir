require "../../func_spec.cr"

# `router.all(['/apps', '/apps/*'], requireStaff)` only calls `next()`.
# It is not seven methods on two paths.
describe "Express middleware-only router.all", tags: "functional" do
  it "keeps the routes that serve and drops the .all rows" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_all_middleware/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    rows = app.endpoints.map { |e| "#{e.method} #{e.url}" }.sort!
    rows.should eq([
      "DELETE /api/apps/installations/:id",
      "GET /api/apps/installations",
      "GET /api/posts",
    ])
    delete_route = app.endpoints.find! { |e| e.method == "DELETE" }
    delete_route.params.map { |p| {p.name, p.param_type} }.should contain({"id", "path"})
  end
end
