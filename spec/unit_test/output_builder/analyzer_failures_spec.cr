require "../../spec_helper"
require "../../../src/output_builder/json"
require "../../../src/output_builder/yaml"
require "../../../src/output_builder/toml"
require "../../../src/output_builder/sarif"
require "../../../src/models/analyzer_failure"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"
require "json"

# The structured formats are the only place a degraded scan is visible to a
# machine: the log line scrolls past in CI, and the endpoint list of a scan
# whose Go analyzer died looks exactly like one for a project with no Go in
# it. These specs pin both halves of that — the failures when there are some,
# and the explicit "none" when there aren't.
private def failure_builder_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
  }
end

private def sample_failures
  [
    AnalyzerFailure.new("go_gin", "Index out of bounds"),
    AnalyzerFailure.new("rust_axum", "Invalid UTF-8 byte sequence"),
  ]
end

private def sample_endpoints
  endpoint = Endpoint.new("/test", "GET")
  endpoint.push_param(Param.new("id", "1", "query"))
  [endpoint]
end

describe "analyzer failures in structured output" do
  describe "OutputBuilderJson" do
    it "emits every failed analyzer under errors" do
      builder = OutputBuilderJson.new(failure_builder_options)
      builder.io = IO::Memory.new
      builder.analyzer_failures = sample_failures

      builder.print(sample_endpoints)
      errors = JSON.parse(builder.io.to_s)["errors"].as_a

      errors.size.should eq(2)
      errors[0]["tech"].as_s.should eq("go_gin")
      errors[0]["message"].as_s.should eq("Index out of bounds")
      errors[1]["tech"].as_s.should eq("rust_axum")
    end

    it "emits an empty errors array when every analyzer succeeded" do
      builder = OutputBuilderJson.new(failure_builder_options)
      builder.io = IO::Memory.new

      builder.print(sample_endpoints)
      json = JSON.parse(builder.io.to_s)

      # Present-but-empty, not absent: a consumer has to be able to read
      # "nothing failed" off the document itself.
      json.as_h.has_key?("errors").should be_true
      json["errors"].as_a.should be_empty
    end
  end

  describe "OutputBuilderYaml" do
    it "emits every failed analyzer under errors" do
      builder = OutputBuilderYaml.new(failure_builder_options)
      builder.io = IO::Memory.new
      builder.analyzer_failures = sample_failures

      builder.print(sample_endpoints)
      errors = YAML.parse(builder.io.to_s)["errors"].as_a

      errors.size.should eq(2)
      errors[0]["tech"].as_s.should eq("go_gin")
      errors[0]["message"].as_s.should eq("Index out of bounds")
    end

    it "emits an empty errors array when every analyzer succeeded" do
      builder = OutputBuilderYaml.new(failure_builder_options)
      builder.io = IO::Memory.new

      builder.print(sample_endpoints)
      yaml = YAML.parse(builder.io.to_s)

      yaml.as_h.has_key?("errors").should be_true
      yaml["errors"].as_a.should be_empty
    end
  end

  describe "OutputBuilderToml" do
    it "emits an [[errors]] table per failed analyzer" do
      builder = OutputBuilderToml.new(failure_builder_options)
      builder.io = IO::Memory.new
      builder.analyzer_failures = sample_failures

      builder.print(sample_endpoints)
      output = builder.io.to_s

      output.should contain("[[errors]]")
      output.should contain("tech = \"go_gin\"")
      output.should contain("message = \"Index out of bounds\"")
      output.should contain("tech = \"rust_axum\"")
    end

    it "writes no errors table when every analyzer succeeded" do
      builder = OutputBuilderToml.new(failure_builder_options)
      builder.io = IO::Memory.new

      builder.print(sample_endpoints)

      # TOML has no spelling for an empty array of tables, so unlike JSON and
      # YAML a clean scan simply has no section here.
      builder.io.to_s.should_not contain("[[errors]]")
    end
  end

  describe "OutputBuilderSarif" do
    it "marks the invocation unsuccessful when an analyzer failed" do
      builder = OutputBuilderSarif.new(failure_builder_options)
      builder.io = IO::Memory.new
      builder.analyzer_failures = sample_failures

      builder.print(sample_endpoints)
      invocations = JSON.parse(builder.io.to_s)["runs"].as_a[0]["invocations"].as_a

      invocations.size.should eq(1)
      invocations[0]["executionSuccessful"].as_bool.should be_false
    end

    it "marks the invocation successful when every analyzer ran" do
      builder = OutputBuilderSarif.new(failure_builder_options)
      builder.io = IO::Memory.new

      builder.print(sample_endpoints)
      invocations = JSON.parse(builder.io.to_s)["runs"].as_a[0]["invocations"].as_a

      invocations.size.should eq(1)
      invocations[0]["executionSuccessful"].as_bool.should be_true
    end
  end
end
