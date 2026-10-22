require "../../engines/javascript_engine"
require "../../../miniparsers/js_http_route_extractor"

module Analyzer::Javascript
  class Deno < JavascriptEngine
    analyzer_for "js_deno"

    def analyze
      files = get_files_by_extensions(Noir::JSHttpRouteExtractor::SOURCE_EXTENSIONS)
      ordered_scan_files(files) do |path|
        Noir::JSHttpRouteExtractor.extract_runtime_serve(path, read_file_content(path), "Deno", @is_debug)
      end.flatten
    end
  end
end
