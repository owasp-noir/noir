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
    PROPERTY_KEYS = {"camel.rest.context-path", "camel.rest.contextPath"}
    # camel-servlet-starter's CamelServlet mapping (`/api/*`), in front of
    # REST DSL routes and `servlet:` consumers.
    SERVLET_KEYS = {"camel.servlet.mapping.context-path", "camel.servlet.mapping.contextPath",
                    "camel.component.servlet.mapping.context-path"}
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
      property_paths = property_values(PROPERTY_KEYS)
      servlet_paths = property_values(SERVLET_KEYS)

      results.each do |(path, result)|
        key = module_key(path)
        context = dsl_paths[key]? || property_paths[key]? || ""
        servlet = servlet_paths[key]?.try(&.rchop("/*").rchop("*")) || ""
        result.routes.each do |route|
          # The servlet component serves REST routes under its mapping and
          # does not prepend `contextPath`, which only describes it.
          # ponytail: assumes the REST component is servlet whenever the
          # mapping is set; reading `component(...)` would settle it.
          url = if route.rest?
                  Noir::URLPath.absolute_join(servlet.empty? ? context : servlet, route.path)
                elsif route.servlet?
                  Noir::URLPath.absolute_join(servlet, route.path)
                else
                  route.path
                end
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

    # `camel.rest.context-path` read as nested YAML keys.
    private def yaml_string(yaml : YAML::Any, key : String) : String?
      node = yaml
      key.split('.').each { |part| node = node.as_h?.try(&.[YAML::Any.new(part)]?) || return }
      node.as_s?.presence
    end

    # The first of `keys` set per module in Spring Boot / Quarkus config.
    private def property_values(keys : Enumerable(String)) : Hash(String, String)
      paths = Hash(String, String).new
      get_files_by_basename("application.properties").each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        properties = read_properties(path)
        if value = keys.compact_map { |key| properties[key]?.presence }.first?
          paths[module_key(path)] ||= value
        end
      end
      SPRING_YAML_FILES.each do |basename|
        get_files_by_basename(basename).each do |path|
          next if JavaEngine.test_path?(base_relative_path(path))
          yaml = YAML.parse(read_file_content(path))
          if value = keys.compact_map { |key| yaml_string(yaml, key) }.first?
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
