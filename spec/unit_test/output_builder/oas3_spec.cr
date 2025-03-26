require "../../spec_helper"
require "../../../src/output_builder/oas3"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOas3" do
  it "print endpoints as OpenAPI 3.0 specification" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOas3.new(options)

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

    # Add a cookie parameter to test OpenAPI 3.0 specific cookie parameter handling
    endpoint3.push_param(Param.new("session", "abc123", "cookie"))

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
  end
end
