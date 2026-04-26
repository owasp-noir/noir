require "../../../models/analyzer"
require "../../../miniparsers/kotlin_ktor_route_extractor_ts"

module Analyzer::Kotlin
  class Ktor < Analyzer
    KOTLIN_EXTENSION = "kt"

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{KOTLIN_EXTENSION}")

        content = read_file_content(path)
        next unless content.includes?("routing")

        Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(content).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterKotlinKtorRouteExtractor::Route, path : String) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param

      # Path placeholders (`{id}`) — emit one path-typed param per
      # placeholder. The optimizer also synthesises these from the
      # URL string, but emitting here keeps parity with the legacy
      # analyzer.
      route.path.scan(/\{([^}]+)\}/) do |match|
        params << Param.new(match[1], "", "path")
      end

      if rt = route.receive_type
        params << Param.new("body", rt, "json")
      end

      route.query_params.each do |name|
        params << Param.new(name, "", "query")
      end

      route.header_params.each do |name|
        params << Param.new(name, "", "header")
      end

      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
