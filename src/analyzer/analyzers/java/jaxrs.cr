require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"
require "xml"

module Analyzer::Java
  class JaxRs < Analyzer
    JAVA_EXTENSION = "java"
    alias ApplicationBaseKey = Tuple(String, String)

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new

      file_list = all_files()
      application_base_paths = application_base_paths_for(file_list)
      derivative_project_roots = derivative_project_roots_for(file_list)
      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next if derivative_project_roots.includes?(project_root_for(path))

        content = read_file_content(path)

        # Cheap pre-filter: only files that mention JAX-RS bindings
        # carry resource classes. Avoids parsing the entire source
        # tree for unrelated `.java` files.
        next unless jaxrs_or_websocket_source?(content)

        # Skip files claimed by a derived framework (Quarkus,
        # Dropwizard) so the same resource class doesn't surface as
        # both `java_jaxrs` and `java_quarkus` endpoints.
        next if claimed_by_derivative?(content)

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          imports = Noir::TreeSitterJavaParameterExtractor.extract_imports_from(root, content)
          dto_index = dto_builder.build_for_with_root(path, content, root)
          bean_index = bean_index_for(path, content, package_name, bean_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields_from(root, content))
          subresource_sources = subresource_sources_for(path, content, package_name, source_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_class_names_from(root, content))
          application_base_path = application_base_path_for(path, package_name, application_base_paths)

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources, include_callees: include_callee).each do |route|
            line = route.line + 1
            details = Details.new(PathInfo.new(route.file_path || path, line))
            endpoint_path = route.protocol == "ws" ? route.path : join_paths(application_base_path, route.path)
            endpoint = Endpoint.new(endpoint_path, route.verb, route.params, details)
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

    private def application_base_paths_for(file_list : Array(String)) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new
      application_packages = Hash(String, Array(ApplicationBaseKey)).new { |hash, key| hash[key] = [] of ApplicationBaseKey }

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless content.includes?("ApplicationPath")
        next unless content.includes?("jakarta.ws.rs") || content.includes?("javax.ws.rs")
        next if claimed_by_derivative?(content)

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?
          project_root = project_root_for(path)
          key = {project_root, package_name}
          next if base_paths.has_key?(key)

          if base_path = Noir::TreeSitterJaxRsExtractor.extract_application_path_from(root, content)
            base_paths[key] = base_path
            Noir::TreeSitterJaxRsExtractor.extract_class_names_from(root, content).each do |class_name|
              add_application_package(application_packages, class_name, key)
              add_application_package(application_packages, "#{package_name}.#{class_name}", key)
            end
          end
        end
      end

      web_xml_base_paths_for(file_list, application_packages).each do |key, base_path|
        base_paths[key] = base_path
      end

      base_paths
    end

    private def derivative_project_roots_for(file_list : Array(String)) : Set(String)
      roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        roots << project_root_for(path) if claimed_by_derivative?(content)
      end

      roots
    end

    private def jaxrs_or_websocket_source?(content : String) : Bool
      content.includes?("jakarta.ws.rs") ||
        content.includes?("javax.ws.rs") ||
        content.includes?("jakarta.websocket") ||
        content.includes?("javax.websocket") ||
        content.includes?("@ServerEndpoint")
    end

    private def add_application_package(application_packages : Hash(String, Array(ApplicationBaseKey)),
                                        class_name : String,
                                        key : ApplicationBaseKey) : Nil
      entries = application_packages[class_name]
      entries << key unless entries.includes?(key)
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

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    private def project_root_for(path : String) : String
      ["/src/main/java/", "/src/main/resources/", "/src/main/webapp/"].each do |marker|
        if index = path.index(marker)
          return path[...index]
        end
      end

      configured_base_for(path)
    end

    private def web_xml_base_paths_for(file_list : Array(String),
                                       application_packages : Hash(String, Array(ApplicationBaseKey))) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new
      global_candidates = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.basename(path) == "web.xml"
        next unless File.exists?(path)

        begin
          project_root = project_root_for(path)
          content = read_file_content(path)
          mappings = parse_web_xml_jaxrs_mappings(content)
          mappings.each do |mapping|
            base_path = normalize_servlet_pattern(mapping[:pattern])
            app_packages = application_packages_for_mapping(mapping[:application_classes], application_packages, project_root)
            if app_packages.empty?
              global_candidates[project_root] << base_path if mapping[:jaxrs_servlet]
            else
              app_packages.each { |key| base_paths[key] = base_path }
            end
          end
        rescue e : Exception
          @logger.debug "Failed to parse JAX-RS web.xml #{path}: #{e.message}"
        end
      end

      global_candidates.each do |project_root, candidates|
        candidates.uniq!
        next unless candidates.size == 1
        next if base_paths.keys.any? { |key| key[0] == project_root }

        keys = application_packages.values.flatten.select { |key| key[0] == project_root }
        keys.uniq!
        keys.each do |key|
          base_paths[key] = candidates.first
        end
      end

      base_paths
    end

    private def application_packages_for_mapping(application_classes : Array(String),
                                                 known_packages : Hash(String, Array(ApplicationBaseKey)),
                                                 project_root : String) : Array(ApplicationBaseKey)
      packages = [] of ApplicationBaseKey

      application_classes.each do |class_name|
        if known = known_packages[class_name]?
          known.each do |key|
            packages << key if key[0] == project_root
          end
          next
        end

        if package_name = package_from_application_class_name(class_name)
          packages << {project_root, package_name}
        end
      end
      packages.uniq!
      packages
    end

    private def parse_web_xml_jaxrs_mappings(content : String) : Array(NamedTuple(pattern: String, application_classes: Array(String), jaxrs_servlet: Bool))
      mappings = [] of NamedTuple(pattern: String, application_classes: Array(String), jaxrs_servlet: Bool)
      doc = XML.parse(content)
      root = find_xml_child(doc, "web-app") || doc
      servlets = Hash(String, NamedTuple(application_classes: Array(String), jaxrs_servlet: Bool)).new

      each_xml_child(root, "servlet") do |servlet|
        name = xml_child_text(servlet, "servlet-name")
        next if name.empty?

        servlet_class = xml_child_text(servlet, "servlet-class")
        application_classes = [] of String
        application_classes << servlet_class unless servlet_class.empty?

        each_xml_child(servlet, "init-param") do |param|
          param_name = xml_child_text(param, "param-name")
          next unless param_name == "javax.ws.rs.Application" || param_name == "jakarta.ws.rs.Application"
          value = xml_child_text(param, "param-value")
          application_classes << value unless value.empty?
        end

        servlets[name] = {
          application_classes: application_classes,
          jaxrs_servlet:       jaxrs_servlet_class?(servlet_class) || application_classes.any? { |value| jaxrs_application_class_name?(value) },
        }
      end

      each_xml_child(root, "servlet-mapping") do |mapping|
        name = xml_child_text(mapping, "servlet-name")
        next if name.empty?
        servlet = servlets[name]?
        next unless servlet

        each_xml_child(mapping, "url-pattern") do |pattern_node|
          pattern = pattern_node.content.strip
          next if pattern.empty?
          mappings << {
            pattern:             pattern,
            application_classes: servlet[:application_classes],
            jaxrs_servlet:       servlet[:jaxrs_servlet],
          }
        end
      end

      mappings
    end

    private def jaxrs_servlet_class?(class_name : String) : Bool
      return false if class_name.empty?
      class_name.includes?("jersey") ||
        class_name.includes?("resteasy") ||
        class_name.includes?("RestEasy") ||
        class_name.includes?("JAXRSServlet") ||
        class_name.includes?("JAXRS") ||
        class_name.includes?("CxfNonSpringJaxrsServlet") ||
        class_name.includes?("CXFNonSpringJaxrsServlet") ||
        class_name.ends_with?(".ServletContainer") ||
        class_name.ends_with?(".HttpServletDispatcher")
    end

    private def jaxrs_application_class_name?(class_name : String) : Bool
      return false if class_name.empty?
      return true if class_name == "javax.ws.rs.core.Application" || class_name == "jakarta.ws.rs.core.Application"
      class_name.includes?(".Application") || class_name.ends_with?("Application")
    end

    private def package_from_application_class_name(class_name : String) : String?
      return unless jaxrs_application_class_name?(class_name)
      return if class_name == "javax.ws.rs.core.Application" || class_name == "jakarta.ws.rs.core.Application"
      return if jaxrs_servlet_class?(class_name)
      index = class_name.rindex('.')
      return unless index
      package_name = class_name[0...index]
      package_name.empty? ? nil : package_name
    end

    private def normalize_servlet_pattern(pattern : String) : String
      cleaned = pattern.strip
      cleaned = cleaned[0...-2] if cleaned.ends_with?("/*")
      cleaned = cleaned[0...-1] if cleaned.size > 1 && cleaned.ends_with?("/")
      return "" if cleaned == "/" || cleaned == "/*"
      cleaned.starts_with?("/") ? cleaned : "/#{cleaned}"
    end

    private def xml_child_text(node : XML::Node, local_name : String) : String
      find_xml_child(node, local_name).try(&.content.strip) || ""
    end

    private def find_xml_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |child|
        return child if child.element? && child.name == local_name
      end
      nil
    end

    private def each_xml_child(node : XML::Node, local_name : String, &)
      node.children.each do |child|
        yield child if child.element? && child.name == local_name
      end
    end

    # Frameworks that ride on JAX-RS but ship their own analyzer.
    # Listing them here keeps the JAX-RS analyzer the fallback for
    # vanilla Jersey / RESTEasy resources without double-counting.
    DERIVATIVE_MARKERS = ["io.quarkus", "io.dropwizard"]

    private def claimed_by_derivative?(content : String) : Bool
      DERIVATIVE_MARKERS.any? { |marker| content.includes?(marker) }
    end

    # Build the cross-file `@BeanParam` index for `path`. Same
    # traversal as the DTO index — current file + same-package
    # siblings + imports — but each file's `extract_bean_fields`
    # result is memoised in the analyzer's per-run cache.
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
        rescue File::NotFoundError
          {} of String => Array(Param)
        end

        beans.each { |name, params| result[name] ||= params }
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
        rescue File::NotFoundError
          ""
        end
        next if body.empty?
        next unless body.includes?("jakarta.ws.rs") || body.includes?("javax.ws.rs")

        class_names = file == path && current_file_class_names ? current_file_class_names : Noir::TreeSitterJaxRsExtractor.extract_class_names(body)
        class_names.each do |name|
          result[name] ||= {file, body}
        end
      end

      result
    end
  end
end
