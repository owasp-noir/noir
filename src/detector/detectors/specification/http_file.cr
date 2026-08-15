require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class HttpFile < Detector
    # Registers `.http` / `.rest` request-file paths in `CodeLocator`.
    detector_for "http_file", extensions: %w[.http .rest], idempotent: false

    # A request line: an HTTP method followed by a target whose first token
    # carries a URL-ish char (`.` `/` `:` `{`). This is the unambiguous
    # signal shared by the VS Code REST Client and JetBrains HTTP Client
    # dialects, and requiring the URL-ish char keeps `.rest` reStructuredText
    # prose ("Get started with the API", "Delete the file") from matching.
    # The verb alternation mirrors `ALLOWED_HTTP_METHODS` — the analyzer
    # parses every verb in that list, so a file whose only request uses one
    # (e.g. `QUERY`) must still be detected here.
    REQUEST_LINE = /^[ \t]*(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT|QUERY)[ \t]+\S*[.\/:{]/im

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, REQUEST_LINE)

      locator = CodeLocator.instance
      locator.push(Noir::LocatorKeys::HTTP_FILE, filename)
      true
    end
  end
end
