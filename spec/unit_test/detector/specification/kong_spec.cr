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
end
