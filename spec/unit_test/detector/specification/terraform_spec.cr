require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Terraform API Gateway config" do
  options = create_test_options
  instance = Detector::Specification::Terraform.new options

  v2_tf = <<-HCL
    resource "aws_apigatewayv2_route" "a" {
      route_key = "GET /items"
    }
    HCL

  rest_tf = <<-HCL
    resource "aws_api_gateway_method" "m" {
      resource_id = aws_api_gateway_resource.users.id
      http_method = "GET"
    }
    HCL

  it "detects a .tf file declaring aws_apigatewayv2_route" do
    locator = CodeLocator.instance
    locator.clear "terraform-spec"

    instance.detect("main.tf", v2_tf).should be_true
    locator.all("terraform-spec").should eq ["main.tf"]
  end

  it "detects a .tf file declaring aws_api_gateway_method" do
    locator = CodeLocator.instance
    locator.clear "terraform-spec"

    instance.detect("api.tf", rest_tf).should be_true
  end

  it "detects a .tf.json file" do
    locator = CodeLocator.instance
    locator.clear "terraform-spec"

    json = %({"resource":{"aws_apigatewayv2_route":{"a":{"route_key":"GET /x"}}}})
    instance.detect("main.tf.json", json).should be_true
  end

  it "rejects .tf without any API Gateway resource" do
    instance.detect("s3.tf", %(resource "aws_s3_bucket" "b" {\n  bucket = "x"\n}\n)).should be_false
  end

  it "rejects non-Terraform files by extension" do
    instance.applicable?("variables.tfvars").should be_false
    instance.detect("template.yaml", v2_tf).should be_false
  end
end
