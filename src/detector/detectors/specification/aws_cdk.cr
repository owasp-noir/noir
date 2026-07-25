require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class AwsCdk < Detector
    # Every `.ts`/`.js`/`.py` in the tree reaches these gates, so each was
    # walking the whole corpus three (hints) plus six (constructs) times.
    TS_JS_HINT_MARKER  = Regex.union("aws-cdk-lib", "@aws-cdk/aws-apigateway", "@aws-cdk/aws-apigatewayv2")
    PYTHON_HINT_MARKER = Regex.union("from aws_cdk", "import aws_cdk", "aws_cdk.aws_apigateway")
    API_CONSTRUCT      = Regex.union("RestApi", "HttpApi", "addResource", "add_resource", "addRoutes", "add_routes")

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      hints = filename.ends_with?(".py") ? PYTHON_HINT_MARKER : TS_JS_HINT_MARKER
      return false unless content_matches?(file_contents, hints)

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
      content_matches?(content, API_CONSTRUCT)
    end
  end
end
