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
      string_constants = Hash(String, String).new
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        Noir::TreeSitterHttp4kExtractor.extract_string_constants(read_file_content(path)).each do |name, value|
          next unless fully_qualified_constant?(name)

          string_constants[name] ||= value
        end
      end

      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?(HTTP4K_MARKER)

        Noir::TreeSitterHttp4kExtractor.extract_routes(content, string_constants, include_callees: include_callee).each do |route|
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
