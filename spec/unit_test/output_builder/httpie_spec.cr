require "../../spec_helper"
require "../../../src/output_builder/httpie"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderHttpie" do
  it "print endpoints as httpie commands" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHttpie.new(options)

    # Create endpoints with various HTTP methods and parameters
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))
    endpoint1.push_param(Param.new("session", "abc123", "cookie"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))
    endpoint2.push_param(Param.new("email", "test@example.com", "json"))
    endpoint2.push_param(Param.new("x-api-key", "key123", "header"))

    endpoint3 = Endpoint.new("/api/products", "PUT")
    endpoint3.push_param(Param.new("product_id", "123", "path"))
    endpoint3.push_param(Param.new("name", "Updated Product", "form"))
    endpoint3.push_param(Param.new("price", "99.99", "form"))

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
  end
end
