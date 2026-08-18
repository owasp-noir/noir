require "../../func_spec.cr"

# `spring.web.resources.static-locations` turns directories into GET
# endpoints, one per file. The analyzer walks those directories itself
# (the endpoint set includes media files, which the index does not carry),
# and that walk used to answer to nothing:
#
#   * `--exclude-path` was ignored, because the option is applied in the
#     detector's walk and only protects `CodeLocator` lookups;
#   * a `file:` location was globbed verbatim, with no containment check
#     against the scan base — `file:/etc/` walked the machine's config
#     directory and emitted an endpoint per file, with absolute
#     `code_paths` leaking the scanning machine's layout into the report.
#
# The fixture declares one location of each shape; the `spring_static_outside`
# directory it points at is deliberately outside the scan base.
empty_count = Hash(Symbol, Int32).new
no_endpoints = [] of Endpoint

file_overrides = Hash(String, YAML::Any).new
file_overrides["exclude_path"] = YAML::Any.new("admin.html")

dir_overrides = Hash(String, YAML::Any).new
dir_overrides["exclude_path"] = YAML::Any.new("src/main/resources/static")

baseline = FunctionalTester.new("fixtures/kotlin/spring_static/", empty_count, no_endpoints)
file_excluded = FunctionalTester.new("fixtures/kotlin/spring_static/", empty_count, no_endpoints, file_overrides)
dir_excluded = FunctionalTester.new("fixtures/kotlin/spring_static/", empty_count, no_endpoints, dir_overrides)

describe "Spring static-locations" do
  it "serves classpath: and in-base file: locations" do
    urls = baseline.endpoints.map(&.url)
    urls.should contain("/index.html")
    urls.should contain("/admin.html")
    urls.should contain("/extra.html")
  end

  it "skips a file: location that resolves outside the scan base" do
    baseline.endpoints.map(&.url).should_not contain("/leaked.html")
  end

  it "honours --exclude-path for a single static file" do
    urls = file_excluded.endpoints.map(&.url)
    urls.should_not contain("/admin.html")
    urls.should contain("/index.html")
  end

  it "honours --exclude-path for a whole static directory" do
    urls = dir_excluded.endpoints.map(&.url)
    urls.should_not contain("/admin.html")
    urls.should_not contain("/index.html")
    # The other location is untouched by the pattern.
    urls.should contain("/extra.html")
  end
end
