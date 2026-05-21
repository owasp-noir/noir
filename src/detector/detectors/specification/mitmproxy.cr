require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Mitmproxy < Detector
    # Tnetstring length prefix: one or more ASCII digits then a colon.
    LENGTH_PREFIX = /\A\d+:/

    # mitmproxy stores its top-level flow type under the dict key
    # "type". In tnetstring that key always serializes verbatim as
    # either `4:type;` (mitmproxy's bytes type) or `4:type,` (the
    # standard tnetstring string type) depending on flow format
    # version, so we accept either variant as the magic marker.
    TYPE_MARKERS = ["4:type;", "4:type,"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.starts_with?(LENGTH_PREFIX)
      return false unless TYPE_MARKERS.any? { |m| file_contents.includes?(m) }

      locator = CodeLocator.instance
      locator.push("mitmproxy-path", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".mitm") ||
        filename.ends_with?(".flow") ||
        filename.ends_with?(".flows")
    end

    def set_name
      @name = "mitmproxy"
    end

    # Registers mitmproxy flow paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
