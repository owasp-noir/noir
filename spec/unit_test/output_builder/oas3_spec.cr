require "../../spec_helper"
require "../../../src/output_builder/oas3"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"
require "json"

describe "OutputBuilderOas3" do
  it "print endpoints as OpenAPI 3.0 specification" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOas3.new(options)
    builder.set_io IO::Memory.new

    # Create endpoints with various HTTP methods and parameters
    endpoint1 = Endpoint.new("/pets/{petId}", "GET")
    endpoint1.push_param(Param.new("petId", "123", "path"))
    endpoint1.push_param(Param.new("api_key", "key123", "header"))

    endpoint2 = Endpoint.new("/pets", "POST")
    endpoint2.push_param(Param.new("name", "Fluffy", "json"))
    endpoint2.push_param(Param.new("type", "cat", "json"))
    endpoint2.push_param(Param.new("content-type", "application/json", "header"))

    endpoint3 = Endpoint.new("/pets/{petId}/photos", "POST")
    endpoint3.push_param(Param.new("petId", "123", "path"))
    endpoint3.push_param(Param.new("file", "photo.jpg", "form"))
    endpoint3.push_param(Param.new("description", "Pet photo", "form"))
    endpoint3.push_param(Param.new("session", "abc123", "cookie"))

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output is valid OpenAPI 3.0 spec
    spec = JSON.parse(output)

    # Check OpenAPI version
    spec["openapi"].as_s.should eq("3.0.0")

    # Check paths exist and have correct structure
    paths = spec["paths"]
    paths.as_h.size.should eq(3)
  end
end
