require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  # Flags Terraform / OpenTofu configuration (`.tf` HCL and `.tf.json`) that
  # declares AWS API Gateway routes, and registers the path so the analyzer can
  # reconstruct endpoints module-wide.
  class Terraform < Detector
    # Resource types that produce endpoints. Markers are quoted so they match a
    # `resource "aws_apigatewayv2_route"` block (HCL) or an `"aws_apigatewayv2_route"`
    # key (JSON) but NOT sibling types that merely share a prefix
    # (`aws_api_gateway_resource_policy`, `aws_api_gateway_method_settings`, …).
    MARKERS = {
      %("aws_apigatewayv2_route"),
      %("aws_api_gateway_method"),
      %("aws_api_gateway_resource"),
    }

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless MARKERS.any? { |marker| file_contents.includes?(marker) }

      CodeLocator.instance.push("terraform-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".tf") || filename.ends_with?(".tf.json")
    end

    def set_name
      @name = "terraform"
    end

    # Registers each Terraform config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
