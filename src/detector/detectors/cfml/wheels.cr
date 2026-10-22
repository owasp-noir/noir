require "../../../models/detector"

module Detector::Cfml
  class Wheels < Detector
    detector_for "cfml_wheels", extensions: %w[.cfm .cfc]

    # The `mapper()` chain in config/routes.cfm, and the framework's own
    # namespace used by application components.
    MAPPER_RE    = /(?<![\w.])mapper\s*\(\s*\)\s*(?:\/\/[^\n]*\n\s*)*\./i
    DSL_RE       = /\.\s*(?:resources|resource|wildcard|root)\s*\(/i
    NAMESPACE_RE = /\bwheels(?:\.|\/)(?:controller|model|migrator|dispatch)\b/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if File.basename(filename).downcase == "routes.cfm"
        return true if content_matches?(file_contents, MAPPER_RE)
        return true if content_matches?(file_contents, DSL_RE)
      end

      content_matches?(file_contents, NAMESPACE_RE)
    end
  end
end
