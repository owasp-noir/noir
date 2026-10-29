require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/kotlin_route_extractor_ts"
require "xml"
require "../../../utils/url_path"
require "../../../utils/top_level_split"
require "../../../utils/xml_comments"

module Analyzer::Java
  class JaxRs < Analyzer
    analyzer_for "java_jaxrs"

    include JavaEngine

    alias ApplicationBaseKey = Tuple(String, String)

    # `jaxrs_or_websocket_source?` gates the per-file tree-sitter parse;
    # one precompiled `Regex.union` scan (PCRE2 JIT, auto-escapes each
    # literal) replaces 5 separate `String#includes?` passes over the
    # same buffer.
    JAXRS_OR_WEBSOCKET_SOURCE_RE = Regex.union(
      "jakarta.ws.rs", "javax.ws.rs", "jakarta.websocket", "javax.websocket", "@ServerEndpoint"
    )

    def analyze
      include_callee = callees_needed?
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new
      custom_verb_cache = Hash(String, Hash(String, String)).new
      kotlin_dto_builder = Noir::TreeSitterKotlinDtoIndex.new

      file_list = all_files()
      application_base_paths = application_base_paths_for(file_list)
      derivative_project_roots = derivative_project_roots_for(file_list)
      file_list.each do |path|
        next unless jvm_source?(path)
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
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

        if path.ends_with?(".kt")
          analyze_kotlin_file(path, content, kotlin_dto_builder, application_base_paths, include_callee)
          next
        end

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          imports = Noir::TreeSitterJavaParameterExtractor.extract_imports_from(root, content)
          dto_index = dto_builder.build_for_with_root(path, content, root)
          bean_index = bean_index_for(path, content, package_name, bean_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields_from(root, content))
          subresource_sources = subresource_sources_for(path, content, package_name, source_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_class_names_from(root, content), dto_builder, bean_cache)
          custom_verb_annotations = custom_verb_index_for(path, content, package_name, custom_verb_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_custom_verb_annotations_from(root, content))
          application_base_path = application_base_path_for(path, package_name, application_base_paths)

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources,
            custom_verb_annotations: custom_verb_annotations, include_callees: include_callee,
            project_constants: java_project_constants(path)).each do |route|
            endpoint_path = route.protocol == "ws" ? route.path : Noir::URLPath.join_trimmed(application_base_path, route.path)
            @result << jvm_route_endpoint(route, endpoint_path, route.file_path || path)
          end
        end
      end

      Fiber.yield
      @result
    end

    private def analyze_kotlin_file(path : String,
                                    content : String,
                                    dto_builder : Noir::TreeSitterKotlinDtoIndex,
                                    application_base_paths : Hash(ApplicationBaseKey, String),
                                    include_callee : Bool)
      Noir::TreeSitter.parse_kotlin(content) do |root|
        package_name = Noir::TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)
        dto_index = dto_builder.build_for_with_root(path, content, root)
        application_base_path = application_base_path_for(path, package_name, application_base_paths)

        Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes_from(root, content, dto_index, include_callees: include_callee).each do |route|
          endpoint_path = route.protocol == "ws" ? route.path : Noir::URLPath.join_trimmed(application_base_path, route.path)
          @result << jvm_route_endpoint(route, endpoint_path, path)
        end
      end
    end

    APPLICATION_PATH_RE = Regex.union("ApplicationPath")
    WS_RS_PACKAGE_RE    = Regex.union("jakarta.ws.rs", "javax.ws.rs")

    private def application_base_paths_for(file_list : Array(String)) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new
      application_packages = Hash(String, Array(ApplicationBaseKey)).new { |hash, key| hash[key] = [] of ApplicationBaseKey }
      servlet_mounts = Hash(ApplicationBaseKey, String).new
      # Keys two mounts claim with different prefixes (e.g. two servlets
      # with no packages in one module): no single prefix is right.
      conflicting_mounts = Set(ApplicationBaseKey).new

      file_list.each do |path|
        next unless jvm_source?(path)
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)

        content = read_file_content(path)
        if content_matches?(content, SERVLET_CONTAINER_RE) && content_matches?(content, ADD_SERVLET_RE)
          mount_root = project_root_for(path)
          programmatic_servlet_mounts(content).each do |package_name, prefix|
            key = {mount_root, package_name}
            existing = servlet_mounts[key]?
            conflicting_mounts << key if existing && existing != prefix
            servlet_mounts[key] = prefix
          end
        end

        # One precompiled matcher per gate instead of a `String#includes?`
        # scan per `.java` file — this walks the whole Java source set.
        next unless content_matches?(content, APPLICATION_PATH_RE)
        next unless content_matches?(content, WS_RS_PACKAGE_RE)
        next if claimed_by_derivative?(content)

        if path.ends_with?(".kt")
          add_kotlin_application_path(path, content, base_paths)
          next
        end

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?
          project_root = project_root_for(path)
          key = {project_root, package_name}
          next if base_paths.has_key?(key)

          if base_path = Noir::TreeSitterJaxRsExtractor.extract_application_path_from(root, content, java_project_constants(path))
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
      conflicting_mounts.each { |key| servlet_mounts.delete(key) }
      base_paths.merge!(servlet_mounts)

      base_paths
    end

    SERVLET_CONTAINER_RE = /\bnew\s+ServletContainer\s*\(/
    ADD_SERVLET_RE       = /\.addServlet\s*\(/
    PACKAGES_CALL_RE     = /\.\s*packages\s*\(([^)]*)\)/
    STRING_LITERAL_RE    = /"([^"\\]*)"/
    IDENTIFIER_RE        = /\A\w+\z/

    # Jersey mounted in code (embedded Jetty), as `{package, prefix}` pairs:
    # `context.addServlet(holder, "/api/*")` where
    # `holder = new ServletHolder(..., new ServletContainer(config))` and
    # `config.packages("demo.resources")`, or
    # `new ServletContainer(new demo.api.ApiConfig())`, keyed by that
    # class's package. A container with neither mounts the whole root (`""`).
    # ponytail: textual and single-file; a config built in another method's
    # local or another file is not followed.
    private def programmatic_servlet_mounts(content : String) : Array(Tuple(String, String))
      mounts = [] of Tuple(String, String)
      code = JavaEngine.strip_comments(content)
      code.scan(ADD_SERVLET_RE) do |match|
        open_idx = match.end(0) - 1
        close_idx = JavaEngine.find_matching_delimiter(code, open_idx, '(', ')')
        next unless close_idx
        args = Noir::TopLevelSplit.split(code[open_idx + 1...close_idx], ',', Noir::TopLevelSplit::Rules::JAVA)
        next unless args.size == 2
        pattern = args[1].strip
        next unless pattern.size >= 2 && pattern.starts_with?('"') && pattern.ends_with?('"')

        call_at = match.begin(0)
        holder = resolve_local(code, args[0].strip, call_at)
        container = holder.match(SERVLET_CONTAINER_RE)
        next unless container
        container_close = JavaEngine.find_matching_delimiter(holder, container.end(0) - 1, '(', ')')
        next unless container_close
        config_arg = holder[container.end(0)...container_close].strip
        config = resolve_local(code, config_arg, call_at)

        packages = [] of String
        config.scan(PACKAGES_CALL_RE) { |call| collect_string_literals(call[1], packages) }
        if config_arg.matches?(IDENTIFIER_RE)
          code[0...call_at].scan(/\b#{Regex.escape(config_arg)}\s*#{PACKAGES_CALL_RE}/) { |call| collect_string_literals(call[1], packages) }
        end
        if packages.empty? && (type = config.match(/\Anew\s+([\w.]+)\s*\(/).try(&.[1]))
          packages << class_package(code, type) unless type == "ResourceConfig" || type.starts_with?("org.glassfish.")
        end
        packages << "" if packages.empty?

        prefix = normalize_servlet_pattern(pattern[1...-1])
        packages.each { |package_name| mounts << {package_name, prefix} }
      end
      mounts
    end

    private def collect_string_literals(text : String, into : Array(String)) : Nil
      text.scan(STRING_LITERAL_RE) { |literal| into << literal[1] }
    end

    # The value of local `name` at `before`: its last assignment
    # (`name = <expr>;`) ahead of that offset, or `name` itself when it is
    # not a plain identifier with one.
    private def resolve_local(code : String, name : String, before : Int32) : String
      return name unless name.matches?(IDENTIFIER_RE)
      value = nil
      code[0...before].scan(/\b#{Regex.escape(name)}\s*=(?!=)\s*([^;]+);/) { |assignment| value = assignment[1].strip }
      value || name
    end

    # Package of class `type` as `code` names it: the qualifier of a dotted
    # name, else its import, else the file's own package.
    private def class_package(code : String, type : String) : String
      if index = type.rindex('.')
        return type[0...index]
      end
      code.match(/\bimport\s+([\w.]+)\.#{Regex.escape(type)}\s*;/).try(&.[1]) ||
        code.match(/\bpackage\s+([\w.]+)\s*;/).try(&.[1]) || ""
    end

    # Manifest basenames a derivative framework can *only* show up in.
    # Helidon MP's own quickstart is the concrete case: its JAX-RS
    # resource classes carry no `io.helidon` import at all — the
    # runtime is pulled in solely via `pom.xml`'s
    # `io.helidon.microprofile.*` dependencies, so a `.java`-only scan
    # would never see the marker and JAX-RS would double-count those
    # routes under `java_jaxrs` too.
    DERIVATIVE_MANIFEST_BASENAMES = Set{"pom.xml", "build.gradle", "build.gradle.kts"}

    private def derivative_project_roots_for(file_list : Array(String)) : Set(String)
      roots = Set(String).new

      file_list.each do |path|
        next unless jvm_source?(path) || DERIVATIVE_MANIFEST_BASENAMES.includes?(File.basename(path))
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)

        content = read_file_content(path)
        roots << project_root_for(path) if claimed_by_derivative?(content)
      end

      roots
    end

    private def jaxrs_or_websocket_source?(content : String) : Bool
      content.matches?(JAXRS_OR_WEBSOCKET_SOURCE_RE)
    end

    private def add_application_package(application_packages : Hash(String, Array(ApplicationBaseKey)),
                                        class_name : String,
                                        key : ApplicationBaseKey) : Nil
      entries = application_packages[class_name]
      entries << key unless entries.includes?(key)
    end

    private def project_root_for(path : String) : String
      # A manifest file (`pom.xml`, `build.gradle` — see
      # `DERIVATIVE_MANIFEST_BASENAMES`) at the module root has no
      # `/src/...` marker to slice on, so it falls back to the raw
      # configured base — which, unlike a marker-sliced root,
      # may carry a trailing slash depending on how `-b` was passed.
      # Strip it so this root compares equal to the marker-derived
      # root for `.java` files in the same module.
      base = configured_base_for(path)
      Noir::PathScope.marker_root(path, base, {"/src/main/java/", "/src/main/kotlin/", "/src/main/resources/", "/src/main/webapp/"}) || base.rstrip('/')
    end

    private def web_xml_base_paths_for(file_list : Array(String),
                                       application_packages : Hash(String, Array(ApplicationBaseKey))) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new
      global_candidates = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }

      file_list.each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.basename(path) == "web.xml"
        next unless File.exists?(path)

        begin
          project_root = project_root_for(path)
          content = read_file_content(path)
          mappings = parse_web_xml_jaxrs_mappings(content)
          mappings.each do |mapping|
            base_path = normalize_servlet_pattern(mapping[:pattern])
            app_packages = application_packages_for_mapping(mapping[:application_classes], application_packages, project_root)
            mapping[:packages].each { |package_name| app_packages << {project_root, package_name} }
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
        # No `@ApplicationPath` class to attach the mapping to: the servlet
        # serves every resource in the module.
        keys << {project_root, ""} if keys.empty?
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

    alias WebXmlServlet = NamedTuple(application_classes: Array(String), packages: Array(String), jaxrs_servlet: Bool)
    alias WebXmlMapping = NamedTuple(pattern: String, application_classes: Array(String), packages: Array(String), jaxrs_servlet: Bool)

    private def parse_web_xml_jaxrs_mappings(content : String) : Array(WebXmlMapping)
      mappings = [] of WebXmlMapping
      doc = Noir::XmlComments.parse(content)
      root = find_xml_child(doc, "web-app") || doc
      servlets = Hash(String, WebXmlServlet).new

      each_xml_child(root, "servlet") do |servlet|
        name = xml_child_text(servlet, "servlet-name")
        next if name.empty?

        servlet_class = xml_child_text(servlet, "servlet-class")
        application_classes = [] of String
        application_classes << servlet_class unless servlet_class.empty?
        packages = [] of String

        each_xml_child(servlet, "init-param") do |param|
          param_name = xml_child_text(param, "param-name")
          value = xml_child_text(param, "param-value")
          if param_name == "jersey.config.server.provider.packages"
            packages.concat(value.split(/[\s,;]+/, remove_empty: true))
          elsif param_name == "javax.ws.rs.Application" || param_name == "jakarta.ws.rs.Application"
            application_classes << value unless value.empty?
          end
        end

        servlets[name] = {
          application_classes: application_classes,
          packages:            packages,
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
            packages:            servlet[:packages],
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
    # `io.helidon.microprofile` routes to `Analyzer::Java::HelidonMp`,
    # which drives this same extractor under the `java_helidon_mp` tech.
    # `io.dropwizard.metrics` is the standalone Metrics library, not the
    # framework (see the detector's copy of this list).
    DERIVATIVE_MARKERS_RE = /io\.quarkus|io\.dropwizard(?!\.metrics)|io\.helidon\.microprofile/

    private def claimed_by_derivative?(content : String) : Bool
      content_matches?(content, DERIVATIVE_MARKERS_RE)
    end
  end
end
