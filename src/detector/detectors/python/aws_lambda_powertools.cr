require "../../../models/detector"

module Detector::Python
  class AwsLambdaPowertools < Detector
    detector_for "python_aws_lambda_powertools", extensions: %w[.py]

    IMPORT_RE   = /^\s*(?:from\s+aws_lambda_powertools\.event_handler(?:\.[\w.]+)?\s+import\b|import\s+aws_lambda_powertools\.event_handler\b)/m
    RESOLVER_RE = /\b(?:APIGateway(?:Rest|Http)Resolver|ALBResolver|LambdaFunctionUrlResolver|VPCLattice(?:V2)?Resolver|BedrockAgentResolver|Router)\b/

    # An `event_handler` import naming one of the REST resolvers (or the
    # `Router` split-route class). Powertools' logger/tracer/metrics
    # imports and the GraphQL `AppSyncResolver` are not REST routing.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      return false unless file_contents.includes?("aws_lambda_powertools")
      file_contents.matches?(IMPORT_RE) && file_contents.matches?(RESOLVER_RE)
    end
  end
end
