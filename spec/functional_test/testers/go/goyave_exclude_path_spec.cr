require "../../func_spec.cr"

# `router.Static(...)` makes every file under the directory a GET
# endpoint, so `GoEngine#resolve_public_dirs_with_glob` walks it directly
# (media files included, which the index does not carry). That walk did not
# apply `--exclude-path`, so an excluded asset was still reported.
empty_count = Hash(Symbol, Int32).new
no_endpoints = [] of Endpoint

overrides = Hash(String, YAML::Any).new
overrides["exclude_path"] = YAML::Any.new("index.html")

baseline = FunctionalTester.new("fixtures/go/goyave/", empty_count, no_endpoints)
excluded = FunctionalTester.new("fixtures/go/goyave/", empty_count, no_endpoints, overrides)

describe "Go static directories with --exclude-path" do
  it "reports files under a registered static directory" do
    baseline.endpoints.map(&.url).should contain("/static/index.html")
  end

  it "drops an excluded static file but keeps the routes" do
    urls = excluded.endpoints.map(&.url)
    urls.should_not contain("/static/index.html")
    urls.should contain("/api/users")
  end
end
