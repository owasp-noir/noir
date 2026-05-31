require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/httpie"
require "../../../src/output_builder/powershell"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "Output Builders Edge Cases" do
  it "handles special characters in curl" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new

    # Test with special characters
    endpoint = Endpoint.new("/api/test", "POST")
    endpoint.push_param(Param.new("message", "Hello 'World'", "json"))
    endpoint.push_param(Param.new("description", "Test \"quotes\" here", "json"))

    builder.print([endpoint])
    output = builder.io.to_s

    # Should properly escape single quotes for shell
    output.should contain("curl -i -X 'POST'")
    output.should contain("--data-raw '{\"message\":\"Hello '\\''World'\\''\"")
    output.should contain("Content-Type: application/json")
  end

  it "handles special characters in httpie" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHttpie.new(options)
    builder.io = IO::Memory.new

    # Test with special characters
    endpoint = Endpoint.new("/api/test", "POST")
    endpoint.push_param(Param.new("message", "Hello 'World'", "json"))
    endpoint.push_param(Param.new("description", "Test \"quotes\" here", "json"))

    builder.print([endpoint])
    output = builder.io.to_s

    # Should use HTTPie's JSON string syntax and shell-escape values
    output.should contain("http 'POST'")
    output.should contain("'message=Hello '\\''World'\\'''")
    output.should_not contain("message:=")
  end

  it "prints httpie form requests as form data" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHttpie.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/api/test", "POST")
    endpoint.push_param(Param.new("display_name", "Jane Doe", "form"))
    endpoint.push_param(Param.new("note", "rock and roll", "form"))
    endpoint.push_param(Param.new("token", "a+b", "form"))

    builder.print([endpoint])
    output = builder.io.to_s

    output.should contain("http --form 'POST' '/api/test'")
    output.should contain("'display_name=Jane Doe'")
    output.should contain("'note=rock and roll'")
    output.should contain("'token=a+b'")
    output.should_not contain("'token=a b'")
  end

  it "handles special characters in powershell" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderPowershell.new(options)
    builder.io = IO::Memory.new

    # Test with special characters
    endpoint = Endpoint.new("/api/test", "POST")
    endpoint.push_param(Param.new("message", "Hello $World", "json"))
    endpoint.push_param(Param.new("description", "Test `backticks` here", "json"))

    builder.print([endpoint])
    output = builder.io.to_s

    # Should properly escape PowerShell special characters
    output.should contain("Invoke-WebRequest -Method \"POST\"")
    output.should contain("application/json")
  end

  it "handles empty values" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }

    endpoint = Endpoint.new("/api/test", "GET")
    endpoint.push_param(Param.new("empty_param", "", "query"))
    endpoint.push_param(Param.new("x-empty-header", "", "header"))

    # Test curl with empty values
    curl = OutputBuilderCurl.new(options)
    curl.io = IO::Memory.new
    curl.print([endpoint])
    curl_output = curl.io.to_s
    curl_output.should contain("curl -i -X 'GET'")

    # Test httpie with empty values
    httpie = OutputBuilderHttpie.new(options)
    httpie.io = IO::Memory.new
    httpie.print([endpoint])
    httpie_output = httpie.io.to_s
    httpie_output.should contain("http 'GET'")

    # Test powershell with empty values
    ps = OutputBuilderPowershell.new(options)
    ps.io = IO::Memory.new
    ps.print([endpoint])
    ps_output = ps.io.to_s
    ps_output.should contain("Invoke-WebRequest -Method \"GET\"")
  end
end
