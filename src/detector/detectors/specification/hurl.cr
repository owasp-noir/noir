require "../../../models/detector"
require "../../../models/code_locator"
require "../../../models/locator_keys"
require "../../../utils/http_symbols"

module Detector::Specification
  class Hurl < Detector
    # Registers Hurl `.hurl` request-file paths in `CodeLocator`.
    detector_for "hurl", extensions: %w[.hurl], idempotent: false

    # A request line: an uppercase method (Hurl methods are case-sensitive)
    # followed by a URL-ish target.
    REQUEST_LINE = /^[ \t]*(?:#{ALLOWED_HTTP_METHODS.join('|')})[ \t]+\S*[.\/:{]/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, REQUEST_LINE)

      CodeLocator.instance.push(Noir::LocatorKeys::HURL_FILE, filename)
      true
    end
  end
end
