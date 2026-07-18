require "../../../spec_helper"
require "file_utils"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/terraform"

# Writes each {filename => content} pair into a shared temp directory (so the
# analyzer's per-module, per-directory grouping is exercised) and runs the
# Terraform analyzer over them.
private def analyze_terraform(files : Hash(String, String))
  dir = File.tempname("tf_module")
  Dir.mkdir_p(dir)
  locator = CodeLocator.instance
  locator.clear "terraform-spec"
  files.each do |name, content|
    path = File.join(dir, name)
    File.write(path, content)
    locator.push "terraform-spec", path
  end

  options = create_test_options
  Analyzer::Specification::Terraform.new(options).analyze
ensure
  FileUtils.rm_rf(dir) if dir
end

private def analyze_single(content : String, name = "main.tf")
  analyze_terraform({name => content})
end

private def tag_descriptions(endpoint : Endpoint, name : String) : Array(String)
  endpoint.tags.select { |t| t.name == name }.map(&.description)
end

describe "Terraform Analyzer" do
  it "extracts API Gateway v2 route_key method + path" do
    endpoints = analyze_single <<-HCL
      resource "aws_apigatewayv2_route" "a" {
        api_id    = aws_apigatewayv2_api.http.id
        route_key = "GET /items"
      }

      resource "aws_apigatewayv2_route" "b" {
        route_key = "POST /items/{id}"
      }
      HCL

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/items", "GET"},
      {"/items/{id}", "POST"},
    ])
    tag_descriptions(endpoints.first, "terraform-apigateway").should eq ["httpapi"]
  end

  it "normalizes ANY and skips WebSocket / catch-all route keys" do
    endpoints = analyze_single <<-HCL
      resource "aws_apigatewayv2_route" "any" {
        route_key = "ANY /webhook"
      }
      resource "aws_apigatewayv2_route" "def" {
        route_key = "$default"
      }
      resource "aws_apigatewayv2_route" "conn" {
        route_key = "$connect"
      }
      HCL

    endpoints.map { |e| {e.url, e.method} }.should eq([{"/webhook", "ANY"}])
  end

  it "walks the REST resource graph across files in the same module" do
    endpoints = analyze_terraform({
      "resources.tf" => <<-HCL,
        resource "aws_api_gateway_rest_api" "this" {
          name = "demo"
        }

        resource "aws_api_gateway_resource" "users" {
          parent_id = aws_api_gateway_rest_api.this.root_resource_id
          path_part = "users"
        }

        resource "aws_api_gateway_resource" "user_id" {
          parent_id = aws_api_gateway_resource.users.id
          path_part = "{id}"
        }
        HCL
      "methods.tf" => <<-HCL,
        resource "aws_api_gateway_method" "list" {
          resource_id = aws_api_gateway_resource.users.id
          http_method = "GET"
        }

        resource "aws_api_gateway_method" "get" {
          resource_id = aws_api_gateway_resource.user_id.id
          http_method = "GET"
        }
        HCL
    })

    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/users", "GET"},
      {"/users/{id}", "GET"},
    ])
    tag_descriptions(endpoints.first, "terraform-apigateway").should eq ["rest"]
  end

  it "emits '/' for a method attached directly to the REST API root" do
    endpoints = analyze_single <<-HCL
      resource "aws_api_gateway_method" "root" {
        resource_id = aws_api_gateway_rest_api.this.root_resource_id
        http_method = "GET"
      }
      HCL

    endpoints.map { |e| {e.url, e.method} }.should eq([{"/", "GET"}])
  end

  it "parses Terraform JSON (.tf.json) with interpolated references" do
    json = <<-JSON
      {
        "resource": {
          "aws_apigatewayv2_route": {
            "ping": { "route_key": "GET /health" }
          },
          "aws_api_gateway_resource": {
            "orders": {
              "parent_id": "${aws_api_gateway_rest_api.this.root_resource_id}",
              "path_part": "orders"
            }
          },
          "aws_api_gateway_method": {
            "list_orders": {
              "resource_id": "${aws_api_gateway_resource.orders.id}",
              "http_method": "POST"
            }
          }
        }
      }
      JSON

    endpoints = analyze_single(json, "main.tf.json")
    endpoints.map { |e| {e.url, e.method} }.sort!.should eq([
      {"/health", "GET"},
      {"/orders", "POST"},
    ])
  end

  # Regression: a brace-heavy block (IAM policy heredoc, jsonencode) placed
  # BEFORE the API Gateway blocks must not desync the HCL brace matcher and
  # swallow the later resources.
  it "survives heredocs and jsonencode braces in earlier blocks" do
    endpoints = analyze_single <<-HCL
      resource "aws_iam_role_policy" "noise" {
        name = "policy-${var.env}"

        policy = <<-POLICY
        {
          "Version": "2012-10-17",
          "Statement": [{ "Effect": "Allow", "Action": "*", "Resource": "*" }]
        }
        POLICY

        inline = jsonencode({
          nested = { deep = { deeper = "}}}}not a real close" } }
        })
      }

      resource "aws_apigatewayv2_route" "after" {
        route_key = "DELETE /widgets/{id}"
      }
      HCL

    endpoints.map { |e| {e.url, e.method} }.should eq([{"/widgets/{id}", "DELETE"}])
  end

  # Real Terraform leans on variables and `for_each`; computed values must not
  # leak out as garbage endpoints.
  it "drops computed / interpolation-only route keys and methods" do
    endpoints = analyze_single <<-HCL
      # bare reference — no literal method/path to extract
      resource "aws_apigatewayv2_route" "each" {
        for_each  = var.routes
        route_key = each.value.route_key
      }

      # interpolation-only path — nothing concrete to route
      resource "aws_apigatewayv2_route" "var_path" {
        route_key = "GET ${var.path}"
      }

      # non-verb method
      resource "aws_apigatewayv2_route" "weird" {
        route_key = "FETCH /things"
      }

      # kept: concrete method + path, even with an embedded interpolation
      resource "aws_apigatewayv2_route" "keep" {
        route_key = "GET /items/${var.id}"
      }
      HCL

    endpoints.map { |e| {e.url, e.method} }.should eq([{"/items/${var.id}", "GET"}])
  end

  it "drops REST methods and resources with computed attributes" do
    endpoints = analyze_terraform({
      "resources.tf" => <<-HCL,
        resource "aws_api_gateway_resource" "dyn" {
          parent_id = aws_api_gateway_rest_api.this.root_resource_id
          path_part = each.value.name
        }
        HCL
      "methods.tf" => <<-HCL,
        resource "aws_api_gateway_method" "computed_method" {
          resource_id = aws_api_gateway_resource.dyn.id
          http_method = each.value.method
        }
        HCL
    })

    endpoints.should be_empty
  end

  it "does not emit a spurious root endpoint for an unresolvable resource reference" do
    # The referenced resource lives outside this module (child module, data
    # source, or a block that failed to parse) so the path can't be rebuilt.
    endpoints = analyze_single <<-HCL
      resource "aws_api_gateway_method" "orphan" {
        resource_id = aws_api_gateway_resource.defined_elsewhere.id
        http_method = "GET"
      }
      HCL

    endpoints.should be_empty
  end

  # Regression: a heredoc inside a list-valued attribute must be skipped whole,
  # not desync the bracket matcher so its contents leak in as attributes.
  it "skips heredocs inside list-valued attributes without leaking their contents" do
    endpoints = analyze_single <<-HCL
      resource "aws_apigatewayv2_route" "x" {
        bodies = [
          <<-EOT
          ] route_key = "GET /injected"
          EOT
        ]
      }
      HCL

    endpoints.should be_empty
  end

  it "ignores non-API-Gateway resources" do
    endpoints = analyze_single <<-HCL
      resource "aws_s3_bucket" "b" {
        bucket = "my-bucket"
      }

      resource "aws_lambda_function" "fn" {
        function_name = "handler"
        handler       = "index.handler"
      }
      HCL

    endpoints.should be_empty
  end
end
