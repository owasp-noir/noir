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
    PROPERTY_KEYS     = {"camel.rest.context-path", "camel.rest.contextPath"}
    SPRING_YAML_FILES = {"application.yml", "application.yaml"}

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

      # DSL `restConfiguration` (first one in walk order) wins over properties.
      dsl_paths = Hash(String, String).new
      results.each do |(path, result)|
        result.context_path.try { |context| dsl_paths[module_key(path)] ||= context }
      end
      property_paths = property_context_paths

      results.each do |(path, result)|
        key = module_key(path)
        context = dsl_paths[key]? || property_paths[key]? || ""
        result.routes.each do |route|
          url = route.rest? ? Noir::URLPath.absolute_join(context, route.path) : route.path
          params = route.params.map { |(name, type)| Param.new(name, "", type) }
          route.body_type.try { |type| params << Param.new("body", type, "json") }
          @result << Endpoint.new(url, route.verb, unique_params(params), Details.new(PathInfo.new(path, route.line + 1)))
        end
      end

      @result
    end

    # Maven/Gradle module (everything before `/src/main/`), else the file's
    # directory. ponytail: one context path per module; several CamelContexts
    # in one module would need per-context scoping.
    private def module_key(path : String) : String
      relative = base_relative_path(path)
      index = relative.index("/src/main/")
      index ? configured_base_for(path).rstrip('/') + relative[...index] : File.dirname(path)
    end

    # `camel.rest.context-path` from Spring Boot / Quarkus config.
    private def property_context_paths : Hash(String, String)
      paths = Hash(String, String).new
      get_files_by_basename("application.properties").each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        properties = read_properties(path)
        if value = PROPERTY_KEYS.compact_map { |key| properties[key]?.presence }.first?
          paths[module_key(path)] ||= value
        end
      end
      SPRING_YAML_FILES.each do |basename|
        get_files_by_basename(basename).each do |path|
          next if JavaEngine.test_path?(base_relative_path(path))
          rest = YAML.parse(read_file_content(path)).dig?("camel", "rest")
          if value = (rest.try(&.["context-path"]?) || rest.try(&.["contextPath"]?)).try(&.as_s?).presence
            paths[module_key(path)] ||= value
          end
        rescue
          # Malformed or multi-document YAML: no context path.
        end
      end
      paths
    end
  end
end
