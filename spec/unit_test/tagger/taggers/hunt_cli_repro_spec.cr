require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/hunt_param.cr"
require "yaml"

def repro_opts
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "HuntParamTagger CLI repro" do
  it "tags CLI flag params with HTTP-vuln classes" do
    tagger = HuntParamTagger.new(repro_opts)

    cobra_serve = Endpoint.new("cli://cobrademo/serve", "CLI", [
      Param.new("port", "", "flag"),
    ])
    cobra_serve.protocol = "cli"

    urfave_root = Endpoint.new("cli://urfavedemo", "CLI", [
      Param.new("config", "", "flag"),
    ])
    urfave_root.protocol = "cli"

    tagger.perform([cobra_serve, urfave_root])

    port_tags = cobra_serve.params[0].tags.map(&.name)
    config_tags = urfave_root.params[0].tags.map(&.name)

    puts "port(flag) tags: #{port_tags}"
    puts "config(flag) tags: #{config_tags}"

    # Assert the buggy behavior to confirm
    port_tags.should contain("ssrf")
    config_tags.should contain("debug")
  end
end
