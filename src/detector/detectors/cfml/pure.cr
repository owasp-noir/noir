require "../../../models/detector"

module Detector::Cfml
  class Pure < Detector
    detector_for "cfml_pure", extensions: %w[.cfm .cfc .cfml]

    # CFML tag markers. Tags are case-insensitive and may be written with
    # or without a closing slash, so match the opening `<cfxxx` prefix only.
    TAG_MARKERS_RE = /<cf(?:component|function|argument|script|set|output|query|param|return|invoke|http|location|include)\b/i

    # cfscript component/function declarations (script syntax, no tags).
    SCRIPT_COMPONENT_RE = /\bcomponent\b[^{;]*\{/i
    SCRIPT_FUNCTION_RE  = /\b(?:remote|public|private|package)\s+(?:\w+\s+)?function\s+\w+\s*\(/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if content_matches?(file_contents, TAG_MARKERS_RE)
      return true if content_matches?(file_contents, SCRIPT_FUNCTION_RE)
      return true if content_matches?(file_contents, SCRIPT_COMPONENT_RE)

      false
    end
  end
end
