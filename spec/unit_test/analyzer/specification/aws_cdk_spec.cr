require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/aws_cdk"

private def analyze_cdk(content : String, ext = ".ts")
  path = File.tempname("cdk", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "aws-cdk-spec"
  locator.push "aws-cdk-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::AwsCdk.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

describe "AWS CDK Analyzer" do
  it "follows TS addResource chains and emits addMethod endpoints" do
    endpoints = analyze_cdk <<-TS
      import * as apigw from 'aws-cdk-lib/aws-apigateway';
      const api = new apigw.RestApi(this, 'Api');
      const users = api.root.addResource('users');
      users.addMethod('GET',  new apigw.LambdaIntegration(listFn));
      users.addMethod('POST', new apigw.LambdaIntegration(createFn));
      const user = users.addResource('{id}');
      user.addMethod('GET',    new apigw.LambdaIntegration(getFn));
      user.addMethod('DELETE', new apigw.LambdaIntegration(deleteFn));
      TS

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/users", "GET"},
      {"/users", "POST"},
      {"/users/{id}", "DELETE"},
      {"/users/{id}", "GET"},
    ])
  end

  it "emits HttpApi addRoutes endpoints" do
    endpoints = analyze_cdk <<-TS
      import { HttpApi, HttpMethod } from 'aws-cdk-lib/aws-apigatewayv2';
      const httpApi = new HttpApi(this, 'HttpApi');
      httpApi.addRoutes({ path: '/me', methods: [HttpMethod.GET], integration: foo });
      httpApi.addRoutes({ path: '/health', methods: [HttpMethod.GET, HttpMethod.POST] });
      TS

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/health", "GET"},
      {"/health", "POST"},
      {"/me", "GET"},
    ])
  end

  it "handles Python CDK source" do
    endpoints = analyze_cdk(<<-PY, ".py")
      from aws_cdk import aws_apigateway as apigw
      api = apigw.RestApi(self, 'Api')
      users = api.root.add_resource('users')
      users.add_method('GET')
      user = users.add_resource('{id}')
      user.add_method('GET')
      PY

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/users", "GET"},
      {"/users/{id}", "GET"},
    ])
  end
end
