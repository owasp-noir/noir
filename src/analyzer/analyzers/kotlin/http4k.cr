require "../../../models/analyzer"
require "../../../miniparsers/http4k_extractor_ts"

module Analyzer::Kotlin
  class Http4k < Analyzer
    KOTLIN_EXTENSION = "kt"
    HTTP4K_MARKER    = "org.http4k"

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)
        next unless path.ends_with?(".#{KOTLIN_EXTENSION}")

        content = File.read(path, encoding: "utf-8", invalid: :skip)
        next unless content.includes?(HTTP4K_MARKER)

        Noir::TreeSitterHttp4kExtractor.extract_routes(content).each do |route|
          @result << build_endpoint(route, path)
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterHttp4kExtractor::Route, path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.form_params.each { |name| params << Param.new(name, "", "form") }
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      Endpoint.new(route.path, route.verb, params, details)
    end
  end
end
