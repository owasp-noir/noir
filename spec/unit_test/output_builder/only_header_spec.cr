require "../../spec_helper"
require "../../../src/output_builder/only-header"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyHeader" do
  it "print only header parameters from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyHeader.new(options)

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
  end
end
