require "../../spec_helper"
require "../../../src/output_builder/json"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"
require "json"

describe "OutputBuilderJson" do
  it "print with only endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderJson.new(options)
    builder.set_io IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("id", "1", "query"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output is valid JSON and contains expected data
    json = JSON.parse(output)
    endpoints_json = json["endpoints"].as_a

    endpoints_json.size.should eq(1)
    first_endpoint = endpoints_json[0]
    first_endpoint["url"].as_s.should eq("/test")
    first_endpoint["method"].as_s.should eq("GET")
    first_endpoint["params"].as_a.size.should eq(1)
  end

  it "print with endpoints and passive results" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderJson.new(options)
    builder.set_io IO::Memory.new

    endpoint = Endpoint.new("/api/users", "POST")
    endpoint.push_param(Param.new("username", "test", "json"))

    # Create passive scan result using the actual model structure
    scan_yaml = YAML.parse(%(
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
    ))
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

    # Verify output is valid JSON and contains both endpoints and passive results
    json = JSON.parse(output)
    json["endpoints"].as_a.size.should eq(1)
    json["passive_results"].as_a.size.should eq(1)

    passive_result = json["passive_results"][0]
    passive_result["file_path"].as_s.should eq("test.cr")
    passive_result["line_number"].as_i.should eq(10)
  end
end
