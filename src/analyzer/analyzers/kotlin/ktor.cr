require "../../../models/analyzer"
require "../../../miniparsers/kotlin_ktor_route_extractor_ts"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  class Ktor < Analyzer
    KOTLIN_EXTENSION = "kt"

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        content = read_file_content(path)
        next unless potential_ktor_route_file?(content)

        Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(content, include_callees: include_callee).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def potential_ktor_route_file?(content : String) : Bool
      content.includes?("routing") ||
        content.includes?("io.ktor.server.routing") ||
        content.includes?("Route.")
    end

    private def build_endpoint(route : Noir::TreeSitterKotlinKtorRouteExtractor::Route, path : String) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param
      path_param_names = Set(String).new

      # Path placeholders (`{id}`) — emit one path-typed param per
      # placeholder. The optimizer also synthesises these from the
      # URL string, but emitting here keeps parity with the legacy
      # analyzer.
      route.path.scan(/\{([^}]+)\}/) do |match|
        path_param_names << match[1]
        params << Param.new(match[1], "", "path")
      end

      if rt = route.receive_type
        params << Param.new("body", rt, "json")
      end

      route.query_params.each do |name|
        next if path_param_names.includes?(name)
        params << Param.new(name, "", "query")
      end

      route.header_params.each do |name|
        params << Param.new(name, "", "header")
      end

      endpoint = Endpoint.new(route.path, route.verb, params, details)

      # 1-hop callees out of the handler lambda body. The Route
      # extractor doesn't know the file path it came from, so attach
      # it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end
  end
end
