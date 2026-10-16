require "../../../spec_helper"
require "../../../../src/models/noir"
require "file_utils"

# The test-tree gate in `SpecificationEngine#each_spec_file` matches the
# scan-base-relative path. A checkout that merely lives under a `tests/`,
# `src/test/`, `fixtures/` ... ancestor must report exactly what it reports
# anywhere else, and a scan based inside a test tree must still see its files.
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

private FIXTURE = "spec/functional_test/fixtures/specification/test_tree_gate"

describe "SpecificationEngine test-tree gate" do
  it "drops spec documents under test trees and keeps the rest" do
    scan_endpoints(FIXTURE).should eq(["GET /health", "GET /pets", "GET /test-env"])
  end

  ["tests", "src/test", "testdata", "fixtures", "Billing.UnitTests", "Service References"].each do |segment|
    it "reports the same endpoints from a checkout under `#{segment}/`" do
      root = File.tempname("noir-test-tree-gate")
      target = File.join(root, segment, "test_tree_gate")

      begin
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(FIXTURE, target)
        scan_endpoints(target).should eq(scan_endpoints(FIXTURE))
      ensure
        FileUtils.rm_rf(root) if Dir.exists?(root)
      end
    end
  end

  it "keeps the documents of a scan based inside a test tree" do
    scan_endpoints(File.join(FIXTURE, "tests")).should eq(["GET /health", "GET /test-input-only"])
  end
end
