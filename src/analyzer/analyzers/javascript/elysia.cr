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

        include_callee = callees_needed?
        Noir::TreeSitterElysiaExtractor.extract_routes(content, include_callee).each do |route|
          @result << build_endpoint(route, path, include_callee)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterElysiaExtractor::Route, path : String, include_callee : Bool) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(route.path, route.verb, params, details)
      attach_route_callees(endpoint, route.callees, path) if include_callee
      endpoint
    end

    private def attach_route_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry), path : String)
      callees.each do |name, _callee_path, line|
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end
    end
  end
end
