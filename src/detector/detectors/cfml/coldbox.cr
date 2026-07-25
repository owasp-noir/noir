require "../../../models/detector"

module Detector::Cfml
  class Coldbox < Detector
    detector_for "cfml_coldbox", extensions: %w[.cfc .cfm]

    # The router DSL and the ColdBox base classes. `coldbox.system` is the
    # framework namespace every ColdBox application references.
    ROUTER_DSL_RE = /(?<![\w.])(?:addRoute|resources)\s*\(|\.\s*to(?:Handler|View|Redirect|Response|ModuleRouting)\s*\(/i
    NAMESPACE_RE  = /coldbox\.system\b/i
    MODULE_RE     = /this\s*\.\s*(?:entryPoint|cfmapping)\s*=/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      base = File.basename(filename).downcase
      if base == "router.cfc"
        return true
      end

      return true if content_matches?(file_contents, NAMESPACE_RE)
      return true if base == "moduleconfig.cfc" && content_matches?(file_contents, MODULE_RE)
      return true if base == "routes.cfm" && content_matches?(file_contents, ROUTER_DSL_RE)

      false
    end
  end
end
