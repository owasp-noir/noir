require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Kong declarative config" do
  options = create_test_options
  instance = Detector::Specification::Kong.new options

  it "detects decK yaml shape" do
    content = <<-YAML
      _format_version: "3.0"
      services:
        - name: users
          routes:
            - paths:
                - /v1/users
      YAML

    instance.detect("kong.yml", content).should be_true
  end

  it "detects KIC CRD shape" do
    content = <<-YAML
      apiVersion: configuration.konghq.com/v1
      kind: KongRoute
      spec:
        paths:
          - /v1/orders
      YAML

    instance.detect("kongroute.yml", content).should be_true
  end

  it "code_locator" do
    content = <<-YAML
      _format_version: "3.0"
      services: []
      YAML

    locator = CodeLocator.instance
    locator.clear "kong-spec"
    instance.detect("kong.yml", content)
    locator.all("kong-spec").should eq(["kong.yml"])
  end

  it "rejects unrelated yaml without kong markers" do
    content = <<-YAML
      version: "3.9"
      services:
        app:
          image: test
      YAML

    instance.detect("docker-compose.yml", content).should be_false
  end

  it "rejects invalid yaml that carries a kong marker" do
    instance.detect("broken.yml", "_format_version: \"3.0\"\n  services: [broken").should be_false
  end

  it "rejects marker-bearing yaml that is not a kong document" do
    content = <<-YAML
      notes: mentions _format_version in a value only
      YAML

    instance.detect("notes.yml", content).should be_false
  end
end
