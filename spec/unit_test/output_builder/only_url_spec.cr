require "../../spec_helper"
require "../../../src/output_builder/only-url"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyUrl" do
  it "print endpoints urls" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyUrl.new(options)

    # Create multiple endpoints with different URLs
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))

    endpoint3 = Endpoint.new("/api/products", "GET")

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
  end
end
