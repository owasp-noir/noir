require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/oas3"
require "../../../src/output_builder/postman"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

# CLI endpoints (protocol "cli") model command-line invocation surfaces, not
# HTTP requests — they must be excluded from HTTP-shaped output (curl/httpie/
# powershell, OpenAPI, Postman) and from active probing/proxy delivery, while
# remaining in the JSON/YAML inventory.
describe "cli endpoint guards" do
  options = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
    "url"     => YAML::Any.new(""),
  }

  http = Endpoint.new("/api/users", "GET")
  cli = Endpoint.new("cli://mytool/serve", "CLI")
  cli.protocol = "cli"
  cli.push_param(Param.new("port", "", "flag"))
  scheme = Endpoint.new("myapp://x", "GET")
  scheme.protocol = "mobile-scheme"
  endpoints = [http, cli, scheme]

  it "Endpoint#cli? identifies the cli protocol only" do
    http.cli?.should be_false
    scheme.cli?.should be_false
    cli.cli?.should be_true
  end

  it "Endpoint#non_http? covers both mobile and cli, not http" do
    http.non_http?.should be_false
    cli.non_http?.should be_true
    scheme.non_http?.should be_true
  end

  it "curl output excludes cli endpoints but keeps HTTP" do
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    out = builder.io.to_s
    out.should contain("/api/users")
    out.should_not contain("cli://")
  end

  it "OAS3 output excludes cli endpoints from paths" do
    builder = OutputBuilderOas3.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    spec = JSON.parse(builder.io.to_s)
    paths = spec["paths"].as_h.keys
    paths.should contain("/api/users")
    paths.any?(&.includes?("cli")).should be_false
  end

  it "Postman output excludes cli (and mobile) endpoints" do
    builder = OutputBuilderPostman.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    out = builder.io.to_s
    out.should_not contain("cli://")
    # The new non_http? guard also closes a pre-existing leak where mobile
    # deep links reached the Postman collection.
    out.should_not contain("myapp://")
  end
end
