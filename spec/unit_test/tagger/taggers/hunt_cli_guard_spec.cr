require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/hunt_param.cr"
require "yaml"

def hunt_cli_opts
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

# HUNT word lists describe HTTP parameter vulnerabilities. A CLI endpoint's
# flag/argument/env inputs are not HTTP inputs (`--port` is where the tool
# listens, not an SSRF vector), so the tagger must skip cli:// endpoints
# entirely while still tagging HTTP params — including mobile deep-link
# query params, which remain attacker-supplied URL inputs.
describe "HuntParamTagger CLI guard" do
  it "does not tag CLI flag/argument/env params" do
    tagger = HuntParamTagger.new(hunt_cli_opts)

    cobra_serve = Endpoint.new("cli://cobrademo/serve", "CLI", [
      Param.new("port", "", "flag"),
      Param.new("target", "", "argument"),
      Param.new("API_URL", "", "env"),
    ])
    cobra_serve.protocol = "cli"

    urfave_root = Endpoint.new("cli://urfavedemo", "CLI", [
      Param.new("config", "", "flag"),
    ])
    urfave_root.protocol = "cli"

    tagger.perform([cobra_serve, urfave_root])

    cobra_serve.params.each do |param|
      param.tags.should be_empty
    end
    urfave_root.params[0].tags.should be_empty
  end

  it "still tags HTTP and mobile deep-link params" do
    tagger = HuntParamTagger.new(hunt_cli_opts)

    http = Endpoint.new("/redirect", "GET", [
      Param.new("url", "", "query"),
    ])

    deep_link = Endpoint.new("myapp://open", "GET", [
      Param.new("redirect", "", "query"),
    ])
    deep_link.protocol = "mobile-scheme"

    tagger.perform([http, deep_link])

    http.params[0].tags.map(&.name).should contain("ssrf")
    deep_link.params[0].tags.map(&.name).should contain("ssrf")
  end
end
