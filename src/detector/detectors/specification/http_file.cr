require "../../../models/detector"
require "../../../models/code_locator"
require "../../../models/locator_keys"
require "../../../utils/http_symbols"

module Detector::Specification
  class HttpFile < Detector
    # Registers `.http` / `.rest` request-file paths in `CodeLocator`.
    detector_for "http_file", extensions: %w[.http .rest], idempotent: false

    # A request line: an HTTP method followed by a target whose first token
    # carries a URL-ish char (`.` `/` `:` `{`). This is the unambiguous
    # signal shared by the VS Code REST Client and JetBrains HTTP Client
    # dialects, and requiring the URL-ish char keeps `.rest` reStructuredText
    # prose ("Get started with the API", "Delete the file") from matching.
    #
    # The alternation is derived from `ALLOWED_HTTP_METHODS` — the analyzer
    # parses every verb in that list, so a file whose only request uses one
    # must still be detected here. `QUERY` alone is matched case-sensitively:
    # unlike the classic verbs, English prose idiomatically puts a URL-ish
    # token right after "Query" ("Query /users for the list."), so the
    # lenient match that is safe for GET/POST would fabricate endpoints from
    # documentation. The analyzer applies the same uppercase rule.
    REQUEST_LINE = /^[ \t]*(?:#{(ALLOWED_HTTP_METHODS - ["QUERY"]).join('|')}|(?-i:QUERY))[ \t]+\S*[.\/:{]/im

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, REQUEST_LINE)

      locator = CodeLocator.instance
      locator.push(Noir::LocatorKeys::HTTP_FILE, filename)
      true
    end
  end
end
