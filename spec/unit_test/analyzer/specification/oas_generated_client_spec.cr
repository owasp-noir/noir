require "../../../spec_helper"
require "../../../../src/models/noir"
require "file_utils"

# `SpecificationEngine#generated_client_spec?` climbs from the document to the
# scan base looking for `.openapi-generator/FILES`. The climb must stop at the
# base: a base pointed inside the SDK, or an SDK manifest in a directory above
# it, is the user's choice and never hides the document.
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

private FIXTURE = "spec/functional_test/fixtures/specification/oas_generated_client"

describe "SpecificationEngine generated client spec gate" do
  it "drops the document of a generated client SDK and keeps a server stub's" do
    scan_endpoints(File.join(FIXTURE, "client_sdk")).should be_empty
    scan_endpoints(File.join(FIXTURE, "server_stub")).should eq(["GET /pets"])
  end

  it "keeps the document when the scan base is inside the SDK" do
    scan_endpoints(File.join(FIXTURE, "client_sdk", "api")).should eq(["GET /vendor/accounts"])
  end

  it "ignores a manifest above the scan base" do
    root = File.tempname("noir-generated-client")

    begin
      FileUtils.mkdir_p(File.join(root, "pkg"))
      FileUtils.cp_r(File.join(FIXTURE, "server_stub", "api"), File.join(root, "pkg", "api"))
      Dir.mkdir_p(File.join(root, ".openapi-generator"))
      File.write(File.join(root, ".openapi-generator", "FILES"), "pkg/api/openapi.yaml\nclient.go\n")

      scan_endpoints(root).should be_empty
      scan_endpoints(File.join(root, "pkg")).should eq(["GET /pets"])
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
