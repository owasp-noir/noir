require "../../../models/detector"

module Detector::Cfml
  class Taffy < Detector
    # The `taffy:uri` / `taffy_uri` resource attribute, or a component
    # extending Taffy's resource base. `taffy.core.api` appears in the
    # application's index.cfm.
    URI_ATTRIBUTE_RE = /taffy[_:]uri\s*=\s*["']/i
    RESOURCE_BASE_RE = /extends\s*=\s*["'](?:taffy\.core\.resource|core\.resource)["']/i
    API_BASE_RE      = /taffy\.core\.api/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if file_contents.matches?(URI_ATTRIBUTE_RE)
      return true if file_contents.matches?(RESOURCE_BASE_RE)
      return true if file_contents.matches?(API_BASE_RE)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfc") || filename.ends_with?(".cfm")
    end

    def set_name
      @name = "cfml_taffy"
    end
  end
end
