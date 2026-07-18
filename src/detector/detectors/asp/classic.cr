require "../../../models/detector"

module Detector::Asp
  class Classic < Detector
    # `<%@ LANGUAGE="VBSCRIPT" %>` page directive, the ASP intrinsic
    # objects, and server-side <script> blocks. `.aspx` is a different
    # extension entirely, so there is no overlap with WebForms.
    DIRECTIVE_RE        = /<%@\s*[\s\S]{0,200}?language\s*=\s*"?(?:vbscript|jscript)"?/i
    INTRINSIC_RE        = /\b(?:Request|Response|Server|Session|Application)\s*\.\s*(?:QueryString|Form|Cookies|ServerVariables|Write|Redirect|CreateObject|MapPath|Contents)/i
    SERVER_SCRIPT_RE    = /<script\b[^>]*\brunat\s*=\s*["']?server["']?/i
    SCRIPT_DELIMITER_RE = /<%[=@]?/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if file_contents.matches?(DIRECTIVE_RE)
      return true if file_contents.matches?(SERVER_SCRIPT_RE)
      return true if file_contents.matches?(SCRIPT_DELIMITER_RE) && file_contents.matches?(INTRINSIC_RE)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".asp") || filename.ends_with?(".asa") || filename.ends_with?(".inc")
    end

    def set_name
      @name = "asp_classic"
    end
  end
end
