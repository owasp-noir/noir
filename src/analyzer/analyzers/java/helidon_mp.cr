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
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
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
        next unless File.exists?(path)
        next unless helidon_mp_manifest_path?(path) || path.ends_with?(".#{JAVA_EXTENSION}")

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
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
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

    private def application_base_path_for(path : String,
                                          package_name : String,
                                          base_paths : Hash(ApplicationBaseKey, String)) : String
      project_root = project_root_for(path)
      keys = base_paths.keys.select { |key| key[0] == project_root }
      keys.sort_by!(&.[1].size)
      keys.reverse_each do |key|
        base_package = key[1]
        next unless package_name == base_package || package_name.starts_with?("#{base_package}.")
        return base_paths[key]
      end
      ""
    end

    private def project_root_for(path : String) : String
      ["/src/main/java/", "/src/"].each do |marker|
        if index = path.index(marker)
          return path[...index]
        end
      end

      # A manifest file (`pom.xml`, `build.gradle`) at the module root
      # has no `/src/...` marker to slice on, so it falls back to the
      # raw configured base — which, unlike the marker-sliced form
      # above, may carry a trailing slash depending on how `-b` was
      # passed. Strip it so this root compares equal to the
      # marker-derived root for `.java` files in the same module.
      configured_base_for(path).rstrip('/')
    end

    private def bean_index_for(path : String,
                               content : String,
                               package_name : String,
                               cache : Hash(String, Hash(String, Array(Param))),
                               imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                               current_file_beans : Hash(String, Array(Param))? = nil) : Hash(String, Array(Param))
      result = Hash(String, Array(Param)).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, JAVA_EXTENSION) do |file|
        beans = cache[file] ||= begin
          if file == path && current_file_beans
            current_file_beans
          else
            body = file == path ? content : read_file_content(file)
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields(body)
          end
        rescue IO::Error
          {} of String => Array(Param)
        end

        beans.each { |name, params| result[name] ||= params }
      end

      result
    end

    private def custom_verb_index_for(path : String,
                                      content : String,
                                      package_name : String,
                                      cache : Hash(String, Hash(String, String)),
                                      imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                                      current_file_verbs : Hash(String, String)? = nil) : Hash(String, String)
      result = Hash(String, String).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, JAVA_EXTENSION) do |file|
        verbs = cache[file] ||= begin
          if file == path && current_file_verbs
            current_file_verbs
          else
            body = file == path ? content : read_file_content(file)
            if jaxrs_source?(body)
              Noir::TreeSitterJaxRsExtractor.extract_custom_verb_annotations(body)
            else
              Hash(String, String).new
            end
          end
        rescue IO::Error
          Hash(String, String).new
        end

        verbs.each { |name, verb| result[name] ||= verb }
      end

      result
    end

    private def subresource_sources_for(path : String,
                                        content : String,
                                        package_name : String,
                                        cache : Hash(String, String),
                                        imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                                        current_file_class_names : Array(String)? = nil) : Hash(String, Noir::TreeSitterJaxRsExtractor::SourceEntry)
      result = Hash(String, Noir::TreeSitterJaxRsExtractor::SourceEntry).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, JAVA_EXTENSION) do |file|
        body = cache[file] ||= begin
          file == path ? content : read_file_content(file)
        rescue IO::Error
          ""
        end
        next if body.empty?
        next unless jaxrs_source?(body)

        class_names = file == path && current_file_class_names ? current_file_class_names : Noir::TreeSitterJaxRsExtractor.extract_class_names(body)
        class_names.each do |name|
          result[name] ||= {file, body}
        end
      end

      result
    end
  end
end
