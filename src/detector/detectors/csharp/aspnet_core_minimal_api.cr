require "../../../models/detector"

module Detector::CSharp
  class AspNetCoreMinimalApi < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      return false if file_contents.includes?("ICarterModule")

      has_http_map = file_contents.matches?(/\.\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods)\s*\(/)
      has_generic_map = file_contents.matches?(/\.\s*Map\s*\(/) && minimal_api_context?(file_contents)

      has_http_map || has_generic_map
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs")
    end

    def set_name
      @name = "cs_aspnet_core_minimal_api"
    end

    private def minimal_api_context?(file_contents : String) : Bool
      file_contents.includes?("WebApplication") ||
        file_contents.includes?("IEndpointRouteBuilder") ||
        file_contents.includes?("RouteGroupBuilder")
    end
  end
end
