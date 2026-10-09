require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/camel_route_extractor"
require "../../../utils/url_path"

module Analyzer::Java
  # Apache Camel REST DSL and HTTP consumer routes (Java, XML and YAML DSL).
  # `restConfiguration().contextPath` is CamelContext-wide and usually lives
  # in a different file than the `rest(...)` definitions, so per-file results
  # are collected first and the prefix is applied per module afterwards.
  class Camel < Analyzer
    include JavaEngine
    analyzer_for "java_camel"

    # Spring Boot / Quarkus spelling of `restConfiguration().contextPath`.
    PROPERTY_KEYS  = {"camel.rest.context-path", "camel.rest.contextPath"}
    MODULE_MARKERS = {"/src/main/java/", "/src/main/resources/"}

    def analyze
      files = get_files_by_extensions([".java", ".xml", ".yaml", ".yml"])
      results = ordered_scan_files(files) do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        content = read_file_content(path)
        result = case File.extname(path)
                 when ".java"
                   Noir::CamelRouteExtractor.extract_java(content) if content.includes?(Noir::CamelRouteExtractor::JAVA_DSL)
                 when ".xml"
                   Noir::CamelRouteExtractor.extract_xml(content) if content.matches?(Noir::CamelRouteExtractor::XML_DSL)
                 else
                   Noir::CamelRouteExtractor.extract_yaml(content) if content.matches?(Noir::CamelRouteExtractor::YAML_DSL)
                 end
        {path, result} if result
      end

      # DSL `restConfiguration` wins over application properties.
      context_paths = property_context_paths
      results.each do |(path, result)|
        result.context_path.try { |context| context_paths[module_key(path)] = context }
      end

      results.each do |(path, result)|
        context = context_paths[module_key(path)]? || ""
        result.routes.each do |route|
          url = route.rest? ? Noir::URLPath.absolute_join(context, route.path) : route.path
          params = route.params.map { |(name, type)| Param.new(name, "", type) }
          route.body_type.try { |type| params << Param.new("body", type, "json") }
          @result << Endpoint.new(url, route.verb, unique_params(params), Details.new(PathInfo.new(path, route.line + 1)))
        end
      end

      @result
    end

    # ponytail: one context path per Maven/Gradle module (or one for a flat
    # tree); several CamelContexts in one module would need per-context scoping.
    private def module_key(path : String) : String
      JavaEngine.marker_root(path, MODULE_MARKERS) || ""
    end

    private def property_context_paths : Hash(String, String)
      paths = Hash(String, String).new
      get_files_by_basename("application.properties").each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        properties = read_properties(path)
        PROPERTY_KEYS.each do |key|
          if value = properties[key]?.presence
            paths[module_key(path)] ||= value
          end
        end
      end
      paths
    end
  end
end
