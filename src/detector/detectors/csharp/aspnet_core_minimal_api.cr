require "../../../models/detector"

module Detector::CSharp
  class AspNetCoreMinimalApi < Detector
    detector_for "cs_aspnet_core_minimal_api", extensions: %w[.cs]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      return false if file_contents.includes?("ICarterModule")

      has_http_map = content_matches?(file_contents, /\.\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods)\s*\(/)
      has_generic_map = content_matches?(file_contents, /\.\s*Map\s*\(/) && minimal_api_context?(file_contents)

      has_http_map || has_generic_map
    end

    private def minimal_api_context?(file_contents : String) : Bool
      file_contents.includes?("WebApplication") ||
        file_contents.includes?("IEndpointRouteBuilder") ||
        file_contents.includes?("RouteGroupBuilder")
    end
  end
end
