require "../../spec_helper"
require "../../../src/output_builder/only-param"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyParam" do
  it "print all parameters from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyParam.new(options)
    builder.io = IO::Memory.new

    # Create endpoints with various parameter types
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))
    endpoint1.push_param(Param.new("session", "abc123", "cookie"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))
    endpoint2.push_param(Param.new("x-api-key", "key123", "header"))
    endpoint2.push_param(Param.new("user_id", "123", "path"))

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output contains each parameter name exactly once
    lines = output.split("\n").reject(&.empty?)
    lines.size.should eq(2) # Total number of unique parameters

    # Check for presence of each parameter
    lines.should contain("id")
    lines.should contain("username")
  end

  it "includes body-typed params, which alias onto the json bucket" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyParam.new(options)
    builder.io = IO::Memory.new

    # NestJS/Nuxt/Nitro/Rocket/Servant/Scotty/Cowboy/Elli/Wisp/Drogon/oatpp all
    # record a request-body field as `param_type == "body"`, which resolves to
    # the `json` bucket via `Param#request_type`. Matching on the raw
    # `param_type` dropped them from this format entirely.
    endpoint = Endpoint.new("/admin/upload", "POST")
    endpoint.push_param(Param.new("avatar", "", "body"))
    endpoint.push_param(Param.new("file", "", "body"))
    endpoint.push_param(Param.new("include", "", "query"))
    endpoint.push_param(Param.new("authorization", "", "header"))

    builder.print([endpoint])
    lines = builder.io.to_s.split("\n").reject(&.empty?)

    lines.should contain("avatar")
    lines.should contain("file")
    lines.should contain("include")
    # Headers are not a fuzzable body/query bucket, so they stay out.
    lines.should_not contain("authorization")
  end
end
