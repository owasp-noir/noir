require "../../spec_helper"
require "../../../src/output_builder/powershell"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderPowershell" do
  it "print endpoints as PowerShell Invoke-WebRequest commands" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderPowershell.new(options)
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

    # Verify output contains valid PowerShell Invoke-WebRequest commands
    lines = output.split("\n").reject(&.empty?)

    # Check GET request
    get_line = lines[0]
    get_line.should start_with("Invoke-WebRequest -Method \"GET\"")
    get_line.should contain("/test")
    get_line.should contain("id=1")
    get_line.should contain("Cookie")
    get_line.should contain("session=abc123")

    # Check POST request with JSON
    post_line = lines[1]
    post_line.should start_with("Invoke-WebRequest -Method \"POST\"")
    post_line.should contain("/api/users")
    post_line.should contain("x-api-key")
    post_line.should contain("key123")
    post_line.should contain("application/json")

    # Check PUT request with form data
    put_line = lines[2]
    put_line.should start_with("Invoke-WebRequest -Method \"PUT\"")
    put_line.should contain("/api/products")
    put_line.should contain("name=Updated Product")
    put_line.should contain("application/x-www-form-urlencoded")
  end
end
