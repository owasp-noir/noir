require "../../spec_helper"
require "../../../src/output_builder/sarif"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"
require "json"

describe "OutputBuilderSarif" do
  it "print with only endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderSarif.new(options)
    builder.set_io IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("id", "1", "query"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output is valid JSON and follows SARIF schema
    json = JSON.parse(output)
    json["version"].as_s.should eq("2.1.0")
    json["$schema"].as_s.should contain("sarif-schema-2.1.0.json")

    runs = json["runs"].as_a
    runs.size.should eq(1)

    tool = runs[0]["tool"]["driver"]
    tool["name"].as_s.should eq("OWASP Noir")
    tool["version"].as_s.should eq("0.24.0")

    results = runs[0]["results"].as_a
    results.size.should eq(1)
    results[0]["ruleId"].as_s.should eq("endpoint-discovery")
    results[0]["level"].as_s.should eq("note")
    results[0]["message"]["text"].as_s.should contain("GET")
    results[0]["message"]["text"].as_s.should contain("/test")
    results[0]["message"]["text"].as_s.should contain("query: id")
  end

  it "print with endpoints and passive results" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderSarif.new(options)
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
    json["version"].as_s.should eq("2.1.0")

    runs = json["runs"].as_a
    results = runs[0]["results"].as_a
    results.size.should eq(2)

    # Check endpoint result
    endpoint_result = results.find { |r| r["ruleId"].as_s == "endpoint-discovery" }
    endpoint_result.should_not be_nil
    if endpoint_result
      endpoint_result["level"].as_s.should eq("note")
      endpoint_result["message"]["text"].as_s.should contain("POST")
    end

    # Check passive scan result
    passive_result_item = results.find { |r| r["ruleId"].as_s == "test-rule" }
    passive_result_item.should_not be_nil
    if passive_result_item
      passive_result_item["level"].as_s.should eq("error")
      passive_result_item["message"]["text"].as_s.should eq("test finding")
      passive_result_item["locations"][0]["physicalLocation"]["artifactLocation"]["uri"].as_s.should eq("test.cr")
      passive_result_item["locations"][0]["physicalLocation"]["region"]["startLine"].as_i.should eq(10)
    end

    # Check rules are defined
    rules = runs[0]["tool"]["driver"]["rules"].as_a
    rules.size.should eq(2)
    rule_ids = rules.map { |r| r["id"].as_s }
    rule_ids.should contain("endpoint-discovery")
    rule_ids.should contain("test-rule")
  end

  it "maps severity levels correctly" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderSarif.new(options)
    builder.set_io IO::Memory.new

    endpoints = [] of Endpoint

    # Test different severity levels
    severities = {"critical" => "error", "high" => "error", "medium" => "warning", "low" => "note"}
    passive_results = [] of PassiveScanResult

    severities.each do |severity, expected_level|
      scan_yaml = YAML.parse(%(
        id: test-#{severity}
        info:
          name: "Test #{severity} Rule"
          author: ["test-author"]
          severity: "#{severity}"
          description: "Test Description"
          reference: ["https://example.com"]
        matchers-condition: "or"
        matchers:
          - type: "regex"
            patterns: ["test"]
            condition: "or"
        category: "test"
        techs: ["*"]
      ))
      passive_scan = PassiveScan.new(scan_yaml)
      passive_results << PassiveScanResult.new(
        passive_scan,
        "test.cr",
        10,
        "test finding"
      )
    end

    builder.print(endpoints, passive_results)
    output = builder.io.to_s

    json = JSON.parse(output)
    runs = json["runs"].as_a
    results = runs[0]["results"].as_a

    severities.each do |severity, expected_level|
      result = results.find { |r| r["ruleId"].as_s == "test-#{severity}" }
      result.should_not be_nil
      if result
        result["level"].as_s.should eq(expected_level)
      end
    end
  end
end
