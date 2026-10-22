require "../../spec_helper"
require "../../../src/output_builder/jsonl"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"
require "json"

describe "OutputBuilderJsonl" do
  it "print endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderJsonl.new(options)
    builder.io = IO::Memory.new

    # Create multiple endpoints to test JSONL format
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
    output = builder.io.to_s

    # Split output into lines and verify each line is valid JSON
    lines = output.split("\n").reject(&.empty?)
    lines.size.should eq(2) # Should have one line per endpoint

    # Verify first endpoint JSON
    first_json = JSON.parse(lines[0])
    first_json["url"].as_s.should eq("/test")
    first_json["method"].as_s.should eq("GET")
    first_json["params"].as_a.size.should eq(1)
    first_json["params"][0]["name"].as_s.should eq("id")
    first_json["params"][0]["value"].as_s.should eq("1")
    first_json["params"][0]["param_type"].as_s.should eq("query")

    # Verify second endpoint JSON
    second_json = JSON.parse(lines[1])
    second_json["url"].as_s.should eq("/api/users")
    second_json["method"].as_s.should eq("POST")
    second_json["params"].as_a.size.should eq(1)
    second_json["params"][0]["name"].as_s.should eq("username")
    second_json["params"][0]["value"].as_s.should eq("test")
    second_json["params"][0]["param_type"].as_s.should eq("json")
  end

  it "writes one line per analyzer failure after the endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderJsonl.new(options)
    builder.io = IO::Memory.new
    builder.analyzer_failures = [AnalyzerFailure.new("go_gin", "boom")]

    builder.print([Endpoint.new("/a", "GET")])
    lines = builder.io.to_s.split("\n").reject(&.empty?)

    lines.size.should eq(2)
    JSON.parse(lines[0])["url"].as_s.should eq("/a")
    failure = JSON.parse(lines[1])
    failure["tech"].as_s.should eq("go_gin")
    failure["message"].as_s.should eq("boom")
  end
end
