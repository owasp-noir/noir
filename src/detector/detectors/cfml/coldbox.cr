require "../../../models/detector"

module Detector::Cfml
  class Coldbox < Detector
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

      return true if file_contents.matches?(NAMESPACE_RE)
      return true if base == "moduleconfig.cfc" && file_contents.matches?(MODULE_RE)
      return true if base == "routes.cfm" && file_contents.matches?(ROUTER_DSL_RE)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfc") || filename.ends_with?(".cfm")
    end

    def set_name
      @name = "cfml_coldbox"
    end
  end
end
