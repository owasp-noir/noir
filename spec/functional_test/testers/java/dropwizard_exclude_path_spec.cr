require "../../func_spec.cr"

# Dropwizard's server YAML sets the URL prefix every endpoint inherits
# (`applicationContextPath` + `rootPath`). The analyzer used to find it
# with `Dir.glob(project_root/*.yml)`, which bypassed `--exclude-path`
# *and* the size gate — an excluded, arbitrarily large YAML was handed
# straight to `YAML.parse`. It now resolves the config through the scanned
# file index, so an excluded config is simply not there.
empty_count = Hash(Symbol, Int32).new
no_endpoints = [] of Endpoint

overrides = Hash(String, YAML::Any).new
overrides["exclude_path"] = YAML::Any.new("config.yml")

baseline = FunctionalTester.new("fixtures/java/dropwizard/", empty_count, no_endpoints)
excluded = FunctionalTester.new("fixtures/java/dropwizard/", empty_count, no_endpoints, overrides)

describe "Dropwizard config discovery with --exclude-path" do
  it "applies the server config when nothing is excluded" do
    baseline.endpoints.map(&.url).should contain("/service/api/hello")
  end

  it "falls back to the default paths when the config file is excluded" do
    urls = excluded.endpoints.map(&.url)
    urls.should contain("/hello")
    urls.should_not contain("/service/api/hello")
  end
end
