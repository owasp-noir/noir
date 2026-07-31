require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# A scan's answer must not depend on where the project sits on disk.
#
# Analyzers, engines and the shared parser layer decide which files to skip
# ("this is a test fixture", "this is vendored", "this is build output") and
# which URL a file-routed handler serves, by matching path substrings. Those
# checks used to run on the ABSOLUTE path, so a directory *above* the scan
# base — one the user never asked noir to reason about — decided the result:
# a clone into `~/work/tests/myapp`, or a CI job that checks out under a
# `test/` step directory, silently reported nothing at all.
#
# Every case below copies a real fixture tree to two locations, scans both,
# and asserts the endpoint sets are identical. `spec/unit_test/analyzer/
# legacy_scan_base_path_spec.cr` covers the same contract for the legacy
# stacks (Classic ASP, CFML) with hand-written sources.
private def scan_endpoints(root : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.sort!.uniq!
ensure
  CodeLocator.instance.clear_all
end

# Copy `fixture` to `<tmp>/<segment>/<name>` and scan that copy. `segment`
# is the hostile ancestor: it never appears inside the fixture itself, so a
# correct scan cannot see it at all.
private def scan_under_segment(fixture : String, segment : String) : Array(String)
  root = File.tempname("noir-scan-base")
  target = File.join(root, segment, File.basename(fixture))

  begin
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp_r(fixture, target)
    scan_endpoints(target)
  ensure
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end

# The path segments each stack's convention filters key off. Picking a
# segment the fixture itself never contains means a correct answer is
# unchanged from the neutral scan, whatever the filter decides.
HOSTILE_ANCESTORS = [
  {"php/laravel", "tests"},
  {"php/laravel", "Tests"},
  {"rust/axum", "tests"},
  {"rust/axum", "benches"},
  {"kotlin/spring", "src/test"},
  {"kotlin/spring", "testData"},
  {"kotlin/spring", "build"},
  {"java/spring", "src/test"},
  {"java/spring", "src/it"},
  {"scala/play", "src/test"},
  {"csharp/aspnet_core_mvc", "test"},
  {"csharp/aspnet_core_mvc", "testassets"},
  {"go/gin", "vendor"},
  {"go/gin", "_work"},
  {"swift/vapor", "Tests"},
  {"swift/vapor", ".build"},
  {"fsharp/giraffe", "tests"},
  {"python/django", "site-packages"},
  {"javascript/express", "node_modules"},
  {"javascript/express", "__tests__"},
  {"javascript/express", "dist"},
  {"javascript/nextjs", "app"},
  {"javascript/nuxtjs", "server"},
  {"javascript/sveltekit", "src"},
  {"javascript/remix", "app"},
  {"javascript/astro", "src"},
  {"javascript/nitro", "routes"},
  {"javascript/fresh", "routes"},
  {"typescript/trpc", "__tests__"},
  {"typescript/trpc", "vendor"},
  {"dart/dart_frog", "routes"},
  {"perl/mojolicious", "t"},
  {"perl/mojolicious", "test"},
  {"crystal/kemal", "test"},
  {"crystal/kemal", "lib"},
  {"clojure/compojure", "test"},
  {"elixir/phoenix", "test"},
  {"lua/lapis", "test"},
  {"cpp/crow", "test"},
  {"haskell/scotty", "test"},
  {"groovy/grails", "src/test"},
  {"zig/httpz", "test"},
  {"mobile/ios", "Tests"},
  {"specification/strapi", "api"},
]

describe "scan results and the scan base path" do
  fixtures_root = "spec/functional_test/fixtures"

  HOSTILE_ANCESTORS.each do |(fixture, segment)|
    it "reports the same #{fixture} endpoints from a base path under `#{segment}/`" do
      fixture_path = File.join(fixtures_root, fixture)
      neutral = scan_under_segment(fixture_path, "neutral-parent")
      hostile = scan_under_segment(fixture_path, segment)

      neutral.should_not be_empty
      hostile.should eq(neutral)
    end
  end

  # `/test/` must match a whole path segment. Before the fix these were
  # substring tests on the absolute path, so a directory merely *starting*
  # with a filtered name matched too.
  it "does not treat a `latest/` or `vendored_libs/` ancestor as a filtered segment" do
    fixture_path = File.join(fixtures_root, "php/laravel")
    neutral = scan_under_segment(fixture_path, "neutral-parent")

    scan_under_segment(fixture_path, "latest").should eq(neutral)
    scan_under_segment(fixture_path, "vendored_libs").should eq(neutral)
  end

  # Pointing noir *at* a directory named `tests` is an explicit request for
  # what is inside it. Relativising handles this naturally — the base's own
  # relative path is empty — but it is the case most likely to regress.
  it "analyzes a project whose scan base is itself named `tests`" do
    fixture_path = File.join(fixtures_root, "php/laravel")
    neutral = scan_under_segment(fixture_path, "neutral-parent")

    root = File.tempname("noir-scan-base-is-tests")
    target = File.join(root, "tests")

    begin
      FileUtils.mkdir_p(root)
      FileUtils.cp_r(fixture_path, target)
      scan_endpoints(target).should eq(neutral)
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
