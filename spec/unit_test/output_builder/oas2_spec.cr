require "../../spec_helper"
require "../../../src/output_builder/oas2"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOas2" do
  it "print endpoints as OpenAPI 2.0 (Swagger) specification" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOas2.new(options)

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

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
  end
end
