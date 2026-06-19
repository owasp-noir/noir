require "../../../models/analyzer"
require "../../../miniparsers/http4k_extractor_ts"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  class Http4k < Analyzer
    KOTLIN_EXTENSION = "kt"
    HTTP4K_MARKER    = "org.http4k"

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
      contract_routes_by_base = Hash(String, Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route))).new do |hash, key|
        hash[key] = Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route)).new
      end
      kotlin_files.each do |path|
        string_constants = string_constants_by_base[configured_base_for(path)]
        content = file_contents[path] = read_file_content(path)
        Noir::TreeSitterHttp4kExtractor.extract_string_constants(content).each do |name, value|
          next unless fully_qualified_constant?(name)

          string_constants[name] ||= value
        end
      end

      kotlin_files.each do |path|
        content = file_contents[path]
        next unless content.includes?("bindContract")

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        Noir::TreeSitterHttp4kExtractor.extract_contract_route_functions(content, string_constants, include_callees: include_callee).each do |name, routes|
          contract_routes_by_base[base][name] ||= [] of Noir::TreeSitterHttp4kExtractor::Route
          contract_routes_by_base[base][name].concat(routes)
        end
      end

      kotlin_files.each do |path|
        content = file_contents[path]
        next unless content.includes?(HTTP4K_MARKER)

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        contract_routes = contract_routes_by_base[base]? || Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route)).new
        Noir::TreeSitterHttp4kExtractor.extract_routes(
          content, string_constants, include_callees: include_callee, contract_routes: contract_routes
        ).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def fully_qualified_constant?(name : String) : Bool
      name.count('.') >= 2
    end

    private def build_endpoint(route : Noir::TreeSitterHttp4kExtractor::Route, path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.form_params.each { |name| params << Param.new(name, "", "form") }
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(route.path, route.verb, params, details)

      # 1-hop callees out of the handler expression. The Route
      # extractor doesn't carry the file path, so attach it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end
  end
end
