require "../../../models/detector"

module Detector::Cfml
  class Fw1 < Detector
    detector_for "cfml_fw1", extensions: %w[.cfc]

    # Applications extend `framework.one`; the routes array and the
    # framework settings struct are the other unambiguous markers.
    BASE_RE     = /extends\s*=\s*["']framework\.one["']/i
    SETTINGS_RE = /\bvariables\s*\.\s*framework\s*=\s*\{/i
    ROUTES_RE   = /\broutes\s*[:=]\s*\[[\s\S]{0,400}?["']\$(?:GET|POST|PUT|PATCH|DELETE|RESOURCES)/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if content_matches?(file_contents, BASE_RE)
      return true if content_matches?(file_contents, ROUTES_RE)
      return true if content_matches?(file_contents, SETTINGS_RE)

      false
    end
  end
end
