require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class AwsCdk < Detector
    TS_JS_HINTS  = ["aws-cdk-lib", "@aws-cdk/aws-apigateway", "@aws-cdk/aws-apigatewayv2"]
    PYTHON_HINTS = ["from aws_cdk", "import aws_cdk", "aws_cdk.aws_apigateway"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      hints = filename.ends_with?(".py") ? PYTHON_HINTS : TS_JS_HINTS
      return false unless hints.any? { |h| file_contents.includes?(h) }

      # Require at least one CDK API surface construct so we don't fire on
      # CDK utility files that contain imports but no endpoint declarations.
      return false unless cdk_api_construct?(file_contents)

      CodeLocator.instance.push("aws-cdk-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
        filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
        filename.ends_with?(".py")
    end

    def set_name
      @name = "aws_cdk"
    end

    # Registers each CDK source path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def cdk_api_construct?(content : String) : Bool
      content.includes?("RestApi") || content.includes?("HttpApi") ||
        content.includes?("addResource") || content.includes?("add_resource") ||
        content.includes?("addRoutes") || content.includes?("add_routes")
    end
  end
end
