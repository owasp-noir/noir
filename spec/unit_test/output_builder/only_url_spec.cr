require "../../spec_helper"
require "../../../src/output_builder/only-url"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyUrl" do
  it "print endpoints urls" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyUrl.new(options)
    builder.set_io IO::Memory.new

    # Create multiple endpoints with different URLs
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))

    endpoint3 = Endpoint.new("/api/products", "GET")

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output contains each URL exactly once
    lines = output.split("\n").reject(&.empty?)
    lines.size.should eq(3)
    lines.should contain("/test?id=1")
    lines.should contain("/api/users")
    lines.should contain("/api/products")

    # URLs should be output in order
    lines[0].should eq("/test?id=1")
    lines[1].should eq("/api/users")
    lines[2].should eq("/api/products")
  end
end
