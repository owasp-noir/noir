require "../../../models/detector"

module Detector::Cfml
  class Pure < Detector
    # CFML tag markers. Tags are case-insensitive and may be written with
    # or without a closing slash, so match the opening `<cfxxx` prefix only.
    TAG_MARKERS_RE = /<cf(?:component|function|argument|script|set|output|query|param|return|invoke|http|location|include)\b/i

    # cfscript component/function declarations (script syntax, no tags).
    SCRIPT_COMPONENT_RE = /\bcomponent\b[^{;]*\{/i
    SCRIPT_FUNCTION_RE  = /\b(?:remote|public|private|package)\s+(?:\w+\s+)?function\s+\w+\s*\(/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if file_contents.matches?(TAG_MARKERS_RE)
      return true if file_contents.matches?(SCRIPT_FUNCTION_RE)
      return true if file_contents.matches?(SCRIPT_COMPONENT_RE)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfm") || filename.ends_with?(".cfc") || filename.ends_with?(".cfml")
    end

    def set_name
      @name = "cfml_pure"
    end
  end
end
