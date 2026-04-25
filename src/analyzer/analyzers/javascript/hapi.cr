require "../../../models/analyzer"
require "../../../miniparsers/hapi_extractor_ts"

module Analyzer::Javascript
  class Hapi < Analyzer
    JS_EXTENSIONS = [".js", ".mjs", ".cjs", ".ts"]
    HAPI_MARKERS  = ["@hapi/hapi", "require('hapi')", "require(\"hapi\")", "from 'hapi'", "from \"hapi\""]

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }

        content = File.read(path, encoding: "utf-8", invalid: :skip)
        next unless HAPI_MARKERS.any? { |m| content.includes?(m) }

        Noir::TreeSitterHapiExtractor.extract_routes(content).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterHapiExtractor::Route, path : String) : Endpoint
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
