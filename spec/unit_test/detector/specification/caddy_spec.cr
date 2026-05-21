require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Caddy config" do
  options = create_test_options
  instance = Detector::Specification::Caddy.new options

  caddyfile = <<-CADDY
    api.example.com {
        handle /v1/* {
            reverse_proxy users:8080
        }
    }
    CADDY

  it "detects Caddyfile by name" do
    locator = CodeLocator.instance
    locator.clear "caddy-spec"

    instance.detect("Caddyfile", caddyfile).should be_true
    locator.all("caddy-spec").should eq ["Caddyfile"]
  end

  it "detects caddy.json with apps.http shape" do
    instance.detect("caddy.json", %({"apps":{"http":{"servers":{}}}})).should be_true
  end

  it "rejects unrelated JSON" do
    instance.detect("config.json", %({"foo":"bar"})).should be_false
  end

  it "rejects arbitrary filename" do
    instance.detect("config.txt", caddyfile).should be_false
  end
end
