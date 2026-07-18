require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class HttpFile < Detector
    # A request line: an HTTP method followed by a target whose first token
    # carries a URL-ish char (`.` `/` `:` `{`). This is the unambiguous
    # signal shared by the VS Code REST Client and JetBrains HTTP Client
    # dialects, and requiring the URL-ish char keeps `.rest` reStructuredText
    # prose ("Get started with the API", "Delete the file") from matching.
    REQUEST_LINE = /^[ \t]*(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT)[ \t]+\S*[.\/:{]/im

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.matches?(REQUEST_LINE)

      locator = CodeLocator.instance
      locator.push("http-file", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".http") || filename.ends_with?(".rest")
    end

    def set_name
      @name = "http_file"
    end

    # Registers `.http` / `.rest` request-file paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
