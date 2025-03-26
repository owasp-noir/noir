require "../../spec_helper"
require "../../../src/output_builder/only-cookie"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyCookie" do
  it "print only cookie parameters from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyCookie.new(options)
    builder.set_io IO::Memory.new

    # Create endpoints with various parameters including cookies
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("session", "abc123", "cookie"))
    endpoint1.push_param(Param.new("auth", "token123", "cookie"))
    endpoint1.push_param(Param.new("x-api-key", "key123", "header")) # Should not appear in output

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("theme", "dark", "cookie"))
    endpoint2.push_param(Param.new("username", "test", "json")) # Should not appear in output

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output contains only cookie parameters
    lines = output.split("\n").reject(&.empty?)
    lines.size.should eq(3) # Should only have the 3 cookie parameters

    # Check that only cookie parameters are present
    lines.should contain("session")
    lines.should contain("auth")
    lines.should contain("theme")

    # Check that non-cookie parameters are not present
    lines.should_not contain("x-api-key")
    lines.should_not contain("username")

    # Cookies should be listed in order of appearance
    lines[0].should eq("session")
    lines[1].should eq("auth")
    lines[2].should eq("theme")
  end
end
