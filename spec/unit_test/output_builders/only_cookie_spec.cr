require "../../spec_helper"
require "../../../src/output_builder/only-cookie"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyCookie" do
  it "print only cookie parameters from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyCookie.new(options)

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
  end
end
