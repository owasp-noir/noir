require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderCurl" do
  it "print endpoints as curl commands" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new

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
    output = builder.io.to_s
    lines = output.split("\n").reject(&.empty?)

    get_line = lines[0]
    get_line.should eq("curl -i -X 'GET' '/test?id=1' --cookie 'session=abc123'")

    post_line = lines[1]
    post_line.should start_with("curl -i -X 'POST' '/api/users'")
    post_line.should contain("--data-raw '{\"username\":\"test\",\"email\":\"test@example.com\"}'")
    post_line.should contain("-H 'Content-Type: application/json'")
    post_line.should contain("-H 'x-api-key: key123'")

    put_line = lines[2]
    put_line.should start_with("curl -i -X 'PUT' '/api/products'")
    put_line.should contain("--data-raw 'name=Updated Product&price=99.99'")
    put_line.should contain("-H 'Content-Type: application/x-www-form-urlencoded'")
  end

  it "expands synthetic ANY methods into concrete curl commands" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new

    builder.print([Endpoint.new("/wildcard", "ANY")])
    lines = builder.io.to_s.split("\n").reject(&.empty?)

    lines.size.should eq(WILDCARD_HTTP_METHODS.size)
    lines.map { |line| line.split("'")[1] }.should eq(WILDCARD_HTTP_METHODS)
    lines.any?(&.includes?("'ANY'")).should be_false
  end
end
