require "../../../models/detector"

module Detector::Cfml
  class Wheels < Detector
    # The `mapper()` chain in config/routes.cfm, and the framework's own
    # namespace used by application components.
    MAPPER_RE    = /(?<![\w.])mapper\s*\(\s*\)\s*(?:\/\/[^\n]*\n\s*)*\./i
    DSL_RE       = /\.\s*(?:resources|resource|wildcard|root)\s*\(/i
    NAMESPACE_RE = /\bwheels(?:\.|\/)(?:controller|model|migrator|dispatch)\b/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if File.basename(filename).downcase == "routes.cfm"
        return true if file_contents.matches?(MAPPER_RE)
        return true if file_contents.matches?(DSL_RE)
      end

      file_contents.matches?(NAMESPACE_RE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfm") || filename.ends_with?(".cfc")
    end

    def set_name
      @name = "cfml_wheels"
    end
  end
end
