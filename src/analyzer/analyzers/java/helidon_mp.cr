require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"
require "../../../utils/url_path"

module Analyzer::Java
  # Helidon MP is MicroProfile: routes are plain JAX-RS
  # (`@Path`/`@GET`/`@POST`/...) resource classes, exactly like Quarkus
  # or vanilla Jersey/RESTEasy. There is no Helidon-specific routing
  # shape to walk here, so — mirroring how `Analyzer::Java::Quarkus`
  # handles the same situation — this analyzer just drives the shared
  # `TreeSitterJaxRsExtractor` against files in project roots that carry
  # a Helidon MP marker, so results are reported as "Helidon" rather
  # than the generic `java_jaxrs` tech. `Analyzer::Java::JaxRs` treats
  # `io.helidon.microprofile` as a derivative marker (see
  # `JaxRs::DERIVATIVE_MARKERS`) so the same routes aren't also emitted
  # under `java_jaxrs`.
  class HelidonMp < Analyzer
    analyzer_for "java_helidon_mp"

    include JavaEngine

    JAVA_EXTENSION     = "java"
    HELIDON_MP_MARKERS = ["io.helidon.microprofile"]
    alias ApplicationBaseKey = Tuple(String, String)

    def analyze
      include_callee = callees_needed?
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new
      custom_verb_cache = Hash(String, Hash(String, String)).new

      file_list = all_files()
      helidon_mp_roots = helidon_mp_project_roots_for(file_list)
      application_base_paths = application_base_paths_for(file_list, helidon_mp_roots)

      file_list.each do |path|
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
        next unless helidon_mp_roots.includes?(project_root_for(path))

        content = read_file_content(path)
        next unless jaxrs_source?(content)

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          imports = Noir::TreeSitterJavaParameterExtractor.extract_imports_from(root, content)
          dto_index = dto_builder.build_for_with_root(path, content, root)
          bean_index = bean_index_for(path, content, package_name, bean_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields_from(root, content))
          subresource_sources = subresource_sources_for(path, content, package_name, source_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_class_names_from(root, content))
          custom_verb_annotations = custom_verb_index_for(path, content, package_name, custom_verb_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_custom_verb_annotations_from(root, content))
          application_base_path = application_base_path_for(path, package_name, application_base_paths)

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources,
            custom_verb_annotations: custom_verb_annotations, include_callees: include_callee).each do |route|
            line = route.line + 1
            details = Details.new(PathInfo.new(route.file_path || path, line))
            endpoint = Endpoint.new(Noir::URLPath.join_trimmed(application_base_path, route.path), route.verb, route.params, details)
            endpoint.protocol = route.protocol
            route.callees.each do |name, callee_line|
              endpoint.push_callee(Callee.new(name, path: route.file_path || path, line: callee_line))
            end
            @result << endpoint
          end
        end
      end

      Fiber.yield
      @result
    end

    JAXRS_SOURCE_RE = Regex.union("jakarta.ws.rs", "javax.ws.rs")

    private def jaxrs_source?(content : String) : Bool
      content.matches?(JAXRS_SOURCE_RE)
    end

    private def helidon_mp_project_roots_for(file_list : Array(String)) : Set(String)
      roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless helidon_mp_manifest_path?(path) || path.ends_with?(".#{JAVA_EXTENSION}")
        next unless File.exists?(path)

        content = read_file_content(path)
        roots << project_root_for(path) if HELIDON_MP_MARKERS.any? { |marker| content.includes?(marker) }
      end

      roots
    end

    private def helidon_mp_manifest_path?(path : String) : Bool
      basename = File.basename(path)
      basename == "pom.xml" || basename == "build.gradle" || basename == "build.gradle.kts"
    end

    private def application_base_paths_for(file_list : Array(String), helidon_mp_roots : Set(String)) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new

      file_list.each do |path|
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
        next unless helidon_mp_roots.includes?(project_root_for(path))

        content = read_file_content(path)
        next unless content.includes?("ApplicationPath")
        next unless jaxrs_source?(content)

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?
          project_root = project_root_for(path)
          key = {project_root, package_name}
          next if base_paths.has_key?(key)

          if base_path = Noir::TreeSitterJaxRsExtractor.extract_application_path_from(root, content)
            base_paths[key] = base_path
          end
        end
      end

      base_paths
    end

    private def project_root_for(path : String) : String
      # A manifest file (`pom.xml`, `build.gradle`) at the module root
      # has no `/src/...` marker to slice on, so it falls back to the
      # raw configured base — which, unlike a marker-sliced root,
      # may carry a trailing slash depending on how `-b` was
      # passed. Strip it so this root compares equal to the
      # marker-derived root for `.java` files in the same module.
      JavaEngine.marker_root(path, {"/src/main/java/", "/src/"}) || configured_base_for(path).rstrip('/')
    end
  end
end
