require "../../../models/analyzer"
require "../../../miniparsers/adonisjs_extractor_ts"

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

        content = File.read(path, encoding: "utf-8", invalid: :skip)
        next unless ADONIS_MARKERS.any? { |m| content.includes?(m) }

        Noir::TreeSitterAdonisJsExtractor.extract_routes(content).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterAdonisJsExtractor::Route, path : String) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param

      # Surface AdonisJS's `:slug` placeholders as path Params for
      # parity with how the optimizer expands `{slug}` elsewhere in
      # the codebase.
      route.path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        params << Param.new(match[1], "", "path")
      end

      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
