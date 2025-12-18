require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/httpie"
require "../../../src/output_builder/powershell"
require "../../../src/models/endpoint"

describe "Output Format Comparison" do
  it "generates commands for all formats" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }

    endpoint = Endpoint.new("/api/test", "POST")
    endpoint.push_param(Param.new("name", "John Doe", "json"))
    endpoint.push_param(Param.new("email", "john@example.com", "json"))
    endpoint.push_param(Param.new("Authorization", "Bearer token123", "header"))
    endpoint.push_param(Param.new("session_id", "abc123xyz", "cookie"))

    puts "\n=== CURL ==="
    curl = OutputBuilderCurl.new(options)
    curl.print([endpoint])

    puts "\n=== HTTPie ==="
    httpie = OutputBuilderHttpie.new(options)
    httpie.print([endpoint])

    puts "\n=== PowerShell ==="
    ps = OutputBuilderPowershell.new(options)
    ps.print([endpoint])
  end
end
