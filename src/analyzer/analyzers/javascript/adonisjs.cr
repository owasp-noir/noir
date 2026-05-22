require "../../../models/analyzer"
require "../../../miniparsers/adonisjs_extractor_ts"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Adonisjs < Analyzer
    JS_EXTENSIONS  = [".js", ".mjs", ".cjs", ".ts"]
    ADONIS_MARKERS = [
      "@adonisjs/core",
      "@ioc:Adonis",
    ]

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }

        content = read_file_content(path)
        next unless ADONIS_MARKERS.any? { |m| content.includes?(m) }
        # Reuse the shared JS test-stub gate so `*.spec.ts` /
        # `*.test.ts` (japa, vitest, jest) AdonisJS test scaffolds
        # don't leak. adonisjs/core's own repo parks ~19 phantom
        # endpoints in `tests/providers.spec.ts` alone.
        next if Noir::JSRouteExtractor.test_stub_only?(path, content)

        include_callee = callees_needed?
        Noir::TreeSitterAdonisJsExtractor.extract_routes(content, include_callee).each do |route|
          @result << build_endpoint(route, path, include_callee)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterAdonisJsExtractor::Route, path : String, include_callee : Bool) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param

      # Surface AdonisJS's `:slug` placeholders as path Params for
      # parity with how the optimizer expands `{slug}` elsewhere in
      # the codebase.
      route.path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        params << Param.new(match[1], "", "path")
      end

      endpoint = Endpoint.new(route.path, route.verb, params, details)
      attach_route_callees(endpoint, route.callees, path) if include_callee
      endpoint
    end

    private def attach_route_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry), path : String)
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path.empty? ? path : callee_path, line: line))
      end
    end
  end
end
