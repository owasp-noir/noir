require "../../engines/javascript_engine"
require "../../../miniparsers/js_http_route_extractor"

module Analyzer::Javascript
  class Http < JavascriptEngine
    HTTP_EXTENSIONS = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".tsx"]

    def analyze
      result = [] of Endpoint

      parallel_file_scan(HTTP_EXTENSIONS) do |path|
        content = read_file_content(path)
        Noir::JSHttpRouteExtractor.extract(path, content, @is_debug).each do |endpoint|
          result << endpoint
        end
      end

      result
    end
  end
end
