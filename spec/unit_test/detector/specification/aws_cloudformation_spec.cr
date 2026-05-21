require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect AWS SAM / CloudFormation templates" do
  options = create_test_options
  instance = Detector::Specification::AwsCloudformation.new options

  sam_yaml = <<-YAML
    AWSTemplateFormatVersion: "2010-09-09"
    Transform: AWS::Serverless-2016-10-31
    Resources:
      Fn:
        Type: AWS::Serverless::Function
        Properties:
          Handler: x
    YAML

  cfn_yaml = <<-YAML
    AWSTemplateFormatVersion: "2010-09-09"
    Resources:
      Api:
        Type: AWS::ApiGateway::RestApi
    YAML

  it "detects SAM template by Transform" do
    locator = CodeLocator.instance
    locator.clear "aws-cloudformation-spec"

    instance.detect("template.yaml", sam_yaml).should be_true
    locator.all("aws-cloudformation-spec").should eq ["template.yaml"]
  end

  it "detects plain CloudFormation template by AWSTemplateFormatVersion" do
    locator = CodeLocator.instance
    locator.clear "aws-cloudformation-spec"

    instance.detect("template.yml", cfn_yaml).should be_true
  end

  it "detects JSON-formatted CloudFormation template" do
    locator = CodeLocator.instance
    locator.clear "aws-cloudformation-spec"

    json = %({"AWSTemplateFormatVersion":"2010-09-09","Resources":{}})
    instance.detect("template.json", json).should be_true
  end

  it "rejects unrelated YAML" do
    instance.detect("config.yaml", "service: x\n").should be_false
  end
end
