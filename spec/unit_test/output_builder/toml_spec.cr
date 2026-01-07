require "../../spec_helper"
require "../../../src/output_builder/toml"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"

describe "OutputBuilderToml" do
  it "print with only endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderToml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("id", "1", "query"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output contains expected TOML structure
    output.should contain("[[endpoints]]")
    output.should contain("url = \"/test\"")
    output.should contain("method = \"GET\"")
  end

  it "print with endpoints and passive results" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderToml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/api/users", "POST")
    endpoint.push_param(Param.new("username", "test", "json"))

    # Create passive scan result using the actual model structure
    scan_yaml = YAML.parse <<-YAML
      id: test-rule
      info:
        name: "Test Rule Name"
        author: ["test-author"]
        severity: "high"
        description: "Test Description"
        reference: ["https://example.com"]
      matchers-condition: "or"
      matchers:
        - type: "regex"
          patterns: ["test"]
          condition: "or"
      category: "secret"
      techs: ["*"]
      YAML
    passive_scan = PassiveScan.new(scan_yaml)
    passive_result = PassiveScanResult.new(
      passive_scan,
      "test.cr",
      10,
      "test finding"
    )

    endpoints = [endpoint]
    passive_results = [passive_result]

    builder.print(endpoints, passive_results)
    output = builder.io.to_s

    # Verify output contains both endpoints and passive results in TOML format
    output.should contain("[[endpoints]]")
    output.should contain("[[passive_results]]")
    output.should contain("file_path = \"test.cr\"")
    output.should contain("line_number = 10")
  end
end
