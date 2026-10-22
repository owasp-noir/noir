require "../../spec_helper"
require "../../../src/models/endpoint"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/oas3"
require "../../../src/utils/curl_command"

# Fourteen analyzers (NestJS, Next.js, Rocket, tRPC, Servant, Play, Scotty,
# Wisp, Cowboy, Elli, plumber, Nuxt, Nitro, …) spell a request-body field
# `body` rather than `json`, but every HTTP-shaped consumer dispatches on the
# six canonical types. `body` landed in a bucket nobody read, so those params
# were invisible in curl, httpie, PowerShell, mermaid, Postman and OAS.
private def body_endpoint : Endpoint
  endpoint = Endpoint.new("/submit", "POST")
  endpoint.params << Param.new("username", "alice", "body")
  endpoint.params << Param.new("password", "s3cret", "body")
  endpoint
end

describe Param do
  it "maps the body type onto the json bucket" do
    Param.new("username", "", "body").request_type.should eq("json")
  end

  it "leaves every canonical type alone" do
    %w[query json form header cookie path].each do |type|
      Param.new("x", "", type).request_type.should eq(type)
    end
  end

  it "keeps param_type as the analyzer recorded it" do
    # The JSON/YAML inventory — and the functional expectations built on it —
    # must still see `body`. Only the consumers' dispatch is canonicalized.
    Param.new("username", "", "body").param_type.should eq("body")
  end
end

describe Endpoint do
  it "folds body params into the json bucket of params_to_hash" do
    hash = body_endpoint.params_to_hash
    hash["json"].should eq({"username" => "alice", "password" => "s3cret"})
    hash.has_key?("body").should be_false
  end
end

describe "body params in HTTP-shaped output" do
  it "reaches the curl request body" do
    # Pre-fix this emitted `curl -i -X 'POST' '/submit'` — no body at all.
    io = IO::Memory.new
    options = create_test_options
    builder = OutputBuilderCurl.new(options)
    builder.io = io
    builder.print([body_endpoint])

    output = io.to_s
    output.should contain("--data-raw")
    output.should contain("username")
    output.should contain("application/json")
  end

  it "reaches the OpenAPI requestBody instead of becoming a query parameter" do
    # Pre-fix these were emitted as `in: query` on a POST.
    io = IO::Memory.new
    options = create_test_options
    builder = OutputBuilderOas3.new(options)
    builder.io = io
    builder.print([body_endpoint])

    doc = JSON.parse(io.to_s)
    operation = doc["paths"]["/submit"]["post"]
    operation["requestBody"]?.should_not be_nil
    properties = operation["requestBody"]["content"]["application/json"]["schema"]["properties"]
    properties["username"]?.should_not be_nil
    (operation["parameters"]?.try(&.as_a) || [] of JSON::Any).should be_empty
  end
end
