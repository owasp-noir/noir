require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Serverless Framework config" do
  options = create_test_options
  instance = Detector::Specification::ServerlessFramework.new options

  yaml = <<-YAML
    service: my-api
    provider:
      name: aws
      stage: dev
    functions:
      listUsers:
        handler: src/users.list
        events:
          - http:
              method: get
              path: /users
    YAML

  it "detects serverless.yml with service + provider + functions" do
    locator = CodeLocator.instance
    locator.clear "serverless-framework-spec"

    instance.detect("serverless.yml", yaml).should be_true
    locator.all("serverless-framework-spec").should eq ["serverless.yml"]
  end

  it "detects serverless.yaml" do
    locator = CodeLocator.instance
    locator.clear "serverless-framework-spec"

    instance.detect("serverless.yaml", yaml).should be_true
  end

  it "detects serverless.json shape" do
    locator = CodeLocator.instance
    locator.clear "serverless-framework-spec"

    json = %({"service":"my-api","provider":{"name":"aws"},"functions":{"a":{"handler":"x"}}})
    instance.detect("serverless.json", json).should be_true
  end

  it "rejects non-Serverless YAML files without the required keys" do
    instance.detect("serverless.yml", "service: x\nprovider:\n  name: aws\n").should be_false
  end

  it "ignores unrelated filenames" do
    instance.detect("config.yml", yaml).should be_false
  end
end
