require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect AWS CDK source" do
  options = create_test_options
  instance = Detector::Specification::AwsCdk.new options

  it "detects TypeScript CDK source" do
    src = <<-TS
      import * as apigw from 'aws-cdk-lib/aws-apigateway';
      const api = new apigw.RestApi(this, 'Api');
      const users = api.root.addResource('users');
      TS

    locator = CodeLocator.instance
    locator.clear "aws-cdk-spec"

    instance.detect("lib/stack.ts", src).should be_true
    locator.all("aws-cdk-spec").should eq ["lib/stack.ts"]
  end

  it "detects Python CDK source" do
    src = <<-PY
      from aws_cdk import aws_apigateway as apigw
      api = apigw.RestApi(self, 'Api')
      users = api.root.add_resource('users')
      PY

    instance.detect("infra/stack.py", src).should be_true
  end

  it "rejects unrelated TS file without CDK import" do
    instance.detect("app.ts", "import express from 'express';\n").should be_false
  end

  it "rejects CDK file with imports but no API surface" do
    src = "import * as cdk from 'aws-cdk-lib';\nconst app = new cdk.App();\n"
    instance.detect("app.ts", src).should be_false
  end
end
