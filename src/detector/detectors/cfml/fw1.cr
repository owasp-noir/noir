require "../../../models/detector"

module Detector::Cfml
  class Fw1 < Detector
    # Applications extend `framework.one`; the routes array and the
    # framework settings struct are the other unambiguous markers.
    BASE_RE     = /extends\s*=\s*["']framework\.one["']/i
    SETTINGS_RE = /\bvariables\s*\.\s*framework\s*=\s*\{/i
    ROUTES_RE   = /\broutes\s*[:=]\s*\[[\s\S]{0,400}?["']\$(?:GET|POST|PUT|PATCH|DELETE|RESOURCES)/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      return true if file_contents.matches?(BASE_RE)
      return true if file_contents.matches?(ROUTES_RE)
      return true if file_contents.matches?(SETTINGS_RE)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cfc")
    end

    def set_name
      @name = "cfml_fw1"
    end
  end
end
