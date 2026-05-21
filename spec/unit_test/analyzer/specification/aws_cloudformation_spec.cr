require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/aws_cloudformation"

private def analyze_template(content : String, ext = ".yaml")
  path = File.tempname("template", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "aws-cloudformation-spec"
  locator.push "aws-cloudformation-spec", path

  options = create_test_options
  analyzer = Analyzer::Specification::AwsCloudformation.new options
  analyzer.analyze
ensure
  File.delete(path) if path && File.exists?(path)
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "AWS CloudFormation / SAM Analyzer" do
  it "extracts SAM Api and HttpApi events" do
    endpoints = analyze_template <<-YAML
      Transform: AWS::Serverless-2016-10-31
      Resources:
        ListUsers:
          Type: AWS::Serverless::Function
          Properties:
            Handler: src/users.list
            Events:
              ApiEvent:
                Type: Api
                Properties:
                  Method: GET
                  Path: /users
              HttpApiEvent:
                Type: HttpApi
                Properties:
                  Method: POST
                  Path: /users
      YAML

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/users", "GET"},
      {"/users", "POST"},
    ])

    httpapi = endpoints.find!(&.method.==("POST"))
    tag_descriptions(httpapi, "sam-event-type").should eq ["httpapi"]
  end

  it "walks CloudFormation ApiGateway Resource graph to build paths" do
    endpoints = analyze_template <<-YAML
      AWSTemplateFormatVersion: "2010-09-09"
      Resources:
        Api:
          Type: AWS::ApiGateway::RestApi
        UsersResource:
          Type: AWS::ApiGateway::Resource
          Properties:
            PathPart: users
            ParentId:
              "Fn::GetAtt": [Api, RootResourceId]
        UserIdResource:
          Type: AWS::ApiGateway::Resource
          Properties:
            PathPart: "{id}"
            ParentId:
              Ref: UsersResource
        ListUsersMethod:
          Type: AWS::ApiGateway::Method
          Properties:
            HttpMethod: GET
            ResourceId:
              Ref: UsersResource
        GetUserMethod:
          Type: AWS::ApiGateway::Method
          Properties:
            HttpMethod: GET
            ResourceId:
              Ref: UserIdResource
      YAML

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/users", "GET"},
      {"/users/{id}", "GET"},
    ])
  end

  it "parses JSON-formatted templates" do
    json = <<-JSON
      {
        "Transform": "AWS::Serverless-2016-10-31",
        "Resources": {
          "Health": {
            "Type": "AWS::Serverless::Function",
            "Properties": {
              "Events": {
                "Ping": {
                  "Type": "HttpApi",
                  "Properties": {"Method": "GET", "Path": "/health"}
                }
              }
            }
          }
        }
      }
      JSON
    endpoints = analyze_template(json, ".json")
    endpoints.size.should eq 1
    endpoints[0].url.should eq "/health"
    endpoints[0].method.should eq "GET"
  end
end
