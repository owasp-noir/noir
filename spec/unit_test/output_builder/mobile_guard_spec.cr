require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/oas3"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

# Mobile deep-link endpoints are app URLs, not HTTP requests — they must be
# excluded from HTTP-shaped output (curl/httpie/powershell, OpenAPI) and from
# active probing/proxy delivery, while remaining in the JSON/YAML inventory.
describe "mobile endpoint guards" do
  options = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
    "url"     => YAML::Any.new(""),
  }

  http = Endpoint.new("/api/users", "GET")
  scheme = Endpoint.new("myapp://complex/:id", "GET")
  scheme.protocol = "mobile-scheme"
  intent = Endpoint.new("intent://com.example.app/.Foo", "GET")
  intent.protocol = "android-intent"
  applink = Endpoint.new("https://app.example.com/", "GET")
  applink.protocol = "universal-link"
  endpoints = [http, scheme, intent, applink]

  it "Endpoint#mobile? identifies the three mobile protocols" do
    http.mobile?.should be_false
    scheme.mobile?.should be_true
    intent.mobile?.should be_true
    applink.mobile?.should be_true
  end

  it "curl output excludes mobile endpoints but keeps HTTP" do
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    out = builder.io.to_s
    out.should contain("/api/users")
    out.should_not contain("myapp://")
    out.should_not contain("intent://")
    out.should_not contain("app.example.com")
  end

  it "OAS3 output excludes mobile endpoints from paths" do
    builder = OutputBuilderOas3.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    spec = JSON.parse(builder.io.to_s)
    paths = spec["paths"].as_h.keys
    paths.should contain("/api/users")
    paths.any? { |p| p.includes?("myapp") || p.includes?("intent") }.should be_false
  end
end
