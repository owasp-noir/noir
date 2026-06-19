require "../../../models/analyzer"
require "../../../miniparsers/kotlin_ktor_route_extractor_ts"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  class Ktor < Analyzer
    KOTLIN_EXTENSION = "kt"

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      file_list = all_files()
      kotlin_files = file_list.select do |path|
        File.exists?(path) &&
          path.ends_with?(".#{KOTLIN_EXTENSION}") &&
          !KotlinEngine.test_path?(path)
      end
      file_contents = Hash(String, String).new
      string_constants_by_base = Hash(String, Hash(String, String)).new do |hash, key|
        hash[key] = Hash(String, String).new
      end
      raw_resources_by_base = Hash(String, Array(Noir::TreeSitterKotlinKtorRouteExtractor::RawResource)).new do |hash, key|
        hash[key] = [] of Noir::TreeSitterKotlinKtorRouteExtractor::RawResource
      end
      kotlin_files.each do |path|
        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]
        content = file_contents[path] = read_file_content(path)
        Noir::TreeSitterKotlinKtorRouteExtractor.extract_string_constants(content).each do |name, value|
          next unless fully_qualified_constant?(name)

          string_constants[name] ||= value
        end

        # `@Resource` classes may live in a shared module separate from
        # the route files (Ktor KMP `commonMain`), so collect them across
        # the whole configured base before composing type-safe-route paths.
        if content.includes?("@Resource")
          raw_resources_by_base[base].concat(Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(content))
        end
      end

      resource_paths_by_base = Hash(String, Hash(String, String)).new
      raw_resources_by_base.each do |base, raw_resources|
        resource_paths_by_base[base] = Noir::TreeSitterKotlinKtorRouteExtractor.compose_resource_paths(raw_resources)
      end

      kotlin_files.each do |path|
        content = file_contents[path]
        next unless potential_ktor_route_file?(content)

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        resource_paths = resource_paths_by_base[base]? || Hash(String, String).new
        Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(content, string_constants, resource_paths, include_callees: include_callee).each do |route|
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

    private def fully_qualified_constant?(name : String) : Bool
      name.count('.') >= 2
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
      elsif route.has_body?
        params << Param.new("body", "", "json")
      end

      route.query_params.each do |name|
        next if path_param_names.includes?(name)
        params << Param.new(name, "", "query")
      end

      route.header_params.each do |name|
        params << Param.new(name, "", "header")
      end

      route.form_params.each do |name|
        params << Param.new(name, "", "form")
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
