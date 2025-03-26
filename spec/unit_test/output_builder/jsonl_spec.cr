require "../../spec_helper"
require "../../../src/output_builder/jsonl"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderJsonl" do
  it "print endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderJsonl.new(options)

    # Create multiple endpoints to test JSONL format
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
  end
end
