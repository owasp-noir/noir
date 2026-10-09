require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Tyk < Detector
    # Registers Tyk classic API definitions (JSON, including dashboard
    # exports) and Tyk Operator `ApiDefinition` resources in `CodeLocator`.
    detector_for "tyk", extensions: %w[.json .yaml .yml], idempotent: false

    JSON_LISTEN_PATH = /"listen_path"\s*:\s*"/
    JSON_DEFINITION  = /"(?:api_id|version_data)"\s*:/
    YAML_API_VERSION = /^\s*apiVersion\s*:\s*["']?tyk\.tyk\.io\//m
    YAML_KIND        = /^\s*kind\s*:\s*["']?ApiDefinition\b/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      found = if filename.ends_with?(".json")
                content_matches?(file_contents, JSON_LISTEN_PATH) && content_matches?(file_contents, JSON_DEFINITION)
              else
                content_matches?(file_contents, YAML_API_VERSION) && content_matches?(file_contents, YAML_KIND)
              end
      CodeLocator.instance.push(Noir::LocatorKeys::TYK_SPEC, filename) if found
      found
    end
  end
end
