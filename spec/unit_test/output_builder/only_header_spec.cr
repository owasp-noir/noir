require "../../spec_helper"
require "../../../src/output_builder/only-header"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyHeader" do
  it "print only header parameters from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyHeader.new(options)
    builder.io = IO::Memory.new

    # Create endpoints with various parameters including headers
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("x-api-key", "key123", "header"))
    endpoint1.push_param(Param.new("authorization", "Bearer token", "header"))
    endpoint1.push_param(Param.new("session", "abc123", "cookie")) # Should not appear in output

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("content-type", "application/json", "header"))
    endpoint2.push_param(Param.new("username", "test", "json")) # Should not appear in output

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output contains only header parameters
    lines = output.split("\n").reject(&.empty?)
    lines.size.should eq(4) # Should only have the 4 header parameters

    # Check that only header parameters are present
    lines.should contain("x-api-key")
    lines.should contain("authorization")
    lines.should contain("content-type")

    # Check that non-header parameters are not present
    lines.should_not contain("session")
    lines.should_not contain("username")

    # Headers should be listed in order of appearance
    lines[0].should eq("x-api-key")
    lines[1].should eq("authorization")
    lines[2].should eq("content-type")
  end
end
