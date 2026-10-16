require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# `scan_base_path_spec.cr` guards that a checkout living under a directory
# named like a convention filter (`test/`, `tests/`, `testdata/`, ...) still
# reports its routes. This file extends that contract to the test-tree gates
# that skip throwaway servers and stubs (Erlang, Dart, Rust, Swift, Scotty,
# Elixir, C/C++, Go `testdata/`, Scala, Clojure).
#
# Each fixture holds routes the gate must keep AND routes it must drop. Scanning
# a copy under a hostile ancestor must give exactly the neutral answer: a gate
# that looked at the ABSOLUTE path would drop every route (the ancestor matches
# for every file) and the hostile scan would come back empty.
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

# Copy `fixture` to `<tmp>/<segment>/<name>` and scan that copy.
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

# {fixture, ancestor segment the gate keys off}. Each fixture contains a
# directory of that name (or its sibling spelling) so the gate fires inside it.
TEST_GATE_HOSTILE_ANCESTORS = [
  {"erlang/test_suites", "test"},
  {"erlang/ifdef_inline", "test"},
  {"dart/shelf_test_dirs", "tests"},
  {"dart/shelf_test_dirs", "testing"},
  {"dart/shelf_test_dirs", "test_utils"},
  {"dart/shelf_test_dirs", "integration_test"},
  {"dart/dart_frog_test_segments", "tests"},
  {"dart/dart_frog_test_segments", "test"},
  {"rust/axum_test_crates", "tests"},
  {"rust/axum_test_crates", "e2e"},
  {"rust/axum_test_crates", "playwright"},
  {"rust/axum_test_crates", "rwf-tests"},
  {"rust/axum_test_crates", "tests-fuzz"},
  {"rust/axum_e2e_names", "e2e"},
  {"swift/vapor_client_receivers", "Benchmarks"},
  {"swift/vapor_client_receivers", "Tests"},
  {"swift/vapor_benchmarks_names", "Benchmarks"},
  {"haskell/scotty_tests", "test"},
  {"haskell/scotty_tests", "spec"},
  {"haskell/scotty_prod_names", "test"},
  {"haskell/scotty_prod_names", "spec"},
  {"elixir/test_support", "test"},
  {"elixir/phoenix_channel_topics", "test"},
  {"elixir/phoenix_channel_multiline", "test"},
  {"c/test_dirs", "test"},
  {"c/test_dirs", "tests"},
  {"cpp/test_dirs", "test"},
  {"cpp/test_dirs", "tests"},
  {"cpp/test_dirs", "unittest"},
  {"go/testdata_dirs", "testdata"},
  {"scala/engine_source_sets", "src/test"},
  {"scala/engine_source_sets", "src/sbt-test"},
  {"clojure/test_trees", "test"},
  {"clojure/test_trees", "perf-test"},
]

describe "test-tree gates and the scan base path" do
  fixtures_root = "spec/functional_test/fixtures"

  TEST_GATE_HOSTILE_ANCESTORS.each do |(fixture, segment)|
    it "reports the same #{fixture} endpoints from a base path under `#{segment}/`" do
      fixture_path = File.join(fixtures_root, fixture)
      neutral = scan_under_segment(fixture_path, "neutral-parent")
      hostile = scan_under_segment(fixture_path, segment)

      neutral.should_not be_empty
      hostile.should eq(neutral)
    end
  end
end
