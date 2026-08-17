require "../../func_spec.cr"

# Quarkus serves everything under `src/main/resources/META-INF/resources`,
# so the analyzer enumerates that directory itself rather than asking the
# file index (which drops media files). That walk never saw
# `--exclude-path`: the option is applied in the detector's walk, which
# only protects analyzers that take their file set from `CodeLocator`. A
# file the user excluded was reported anyway.
empty_count = Hash(Symbol, Int32).new
no_endpoints = [] of Endpoint

overrides = Hash(String, YAML::Any).new
overrides["exclude_path"] = YAML::Any.new("app.js")

baseline = FunctionalTester.new("fixtures/java/quarkus/", empty_count, no_endpoints)
excluded = FunctionalTester.new("fixtures/java/quarkus/", empty_count, no_endpoints, overrides)

describe "Quarkus static resources with --exclude-path" do
  it "reports a META-INF/resources file when nothing is excluded" do
    baseline.endpoints.map(&.url).should contain("/platform/assets/app.js")
  end

  it "drops the excluded file and keeps the rest of the directory" do
    urls = excluded.endpoints.map(&.url)
    urls.should_not contain("/platform/assets/app.js")
    urls.should contain("/platform/index.html")
    urls.should contain("/platform/admin/index.html")
  end
end
