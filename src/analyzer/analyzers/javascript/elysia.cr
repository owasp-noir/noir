require "../../../models/analyzer"
require "../../../miniparsers/elysia_extractor_ts"

module Analyzer::Javascript
  class Elysia < Analyzer
    JS_EXTENSIONS  = [".js", ".mjs", ".cjs", ".ts"]
    ELYSIA_MARKERS = ["from 'elysia'", "from \"elysia\"", "require('elysia')", "require(\"elysia\")"]

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }

        content = read_file_content(path)
        next unless ELYSIA_MARKERS.any? { |m| content.includes?(m) }

        Noir::TreeSitterElysiaExtractor.extract_routes(content).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterElysiaExtractor::Route, path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
