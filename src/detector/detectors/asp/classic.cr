require "../../../models/detector"

module Detector::Asp
  class Classic < Detector
    detector_for "asp_classic", extensions: %w[.asp .asa .inc]

    # `<%@ LANGUAGE="VBSCRIPT" %>` page directive, the ASP intrinsic
    # objects, and server-side <script> blocks. `.aspx` is a different
    # extension entirely, so there is no overlap with WebForms.
    DIRECTIVE_RE        = /<%@\s*[\s\S]{0,200}?language\s*=\s*"?(?:vbscript|jscript)"?/i
    INTRINSIC_RE        = /\b(?:Request|Response|Server|Session|Application)\s*\.\s*(?:QueryString|Form|Cookies|ServerVariables|Write|Redirect|CreateObject|MapPath|Contents)/i
    SERVER_SCRIPT_RE    = /<script\b[^>]*\brunat\s*=\s*["']?server["']?/i
    SCRIPT_DELIMITER_RE = /<%[=@]?/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if content_matches?(file_contents, DIRECTIVE_RE)
      return true if content_matches?(file_contents, SERVER_SCRIPT_RE)
      return true if content_matches?(file_contents, SCRIPT_DELIMITER_RE) && content_matches?(file_contents, INTRINSIC_RE)

      false
    end
  end
end
