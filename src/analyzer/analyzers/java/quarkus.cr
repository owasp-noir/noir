require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"
require "yaml"

module Analyzer::Java
  # Quarkus is JAX-RS-flavoured, so this analyzer just drives the
  # shared `TreeSitterJaxRsExtractor` against files in project roots
  # that carry a Quarkus marker. Resource classes are often plain
  # Jakarta REST and do not import Quarkus directly. The extractor
  # already understands Quarkus's
  # `@RestPath` / `@RestQuery` / `@RestHeader` / `@RestForm` /
  # `@RestCookie` shorthand annotations alongside the standard
  # JAX-RS names, so no Quarkus-specific tree walking is needed.
  class Quarkus < Analyzer
    JAVA_EXTENSION  = "java"
    QUARKUS_MARKERS = ["io.quarkus", "quarkus.io"]
    alias ApplicationBaseKey = Tuple(String, String)

    private struct QuarkusPathConfig
      getter http_root_path : String
      getter rest_path : String
      getter static_index_page : String

      def initialize(@http_root_path = "", @rest_path = "", @static_index_page = "index.html")
      end
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new

      file_list = all_files()
      path_configs = path_configs_for(file_list)
      quarkus_roots = quarkus_project_roots_for(file_list)
      application_base_paths = application_base_paths_for(file_list, quarkus_roots)

      path_configs.each do |project_root, path_config|
        next unless quarkus_roots.includes?(project_root)

        extract_static_resource_endpoints(project_root, path_config).each do |endpoint|
          @result << endpoint
        end
      end

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next unless quarkus_roots.includes?(project_root_for(path))

        content = read_file_content(path)
        next unless quarkus_route_source?(content)

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
          configured_base_path = configured_base_path_for(path, path_configs, application_base_path)

          extract_reactive_route_endpoints(content, path, path_configs, include_callee).each do |endpoint|
            @result << endpoint
          end

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources, include_callees: include_callee).each do |route|
            line = route.line + 1
            details = Details.new(PathInfo.new(route.file_path || path, line))
            endpoint = Endpoint.new(join_paths(configured_base_path, route.path), route.verb, route.params, details)
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

    private def quarkus_project_roots_for(file_list : Array(String)) : Set(String)
      roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        roots << project_root_for(path) if QUARKUS_MARKERS.any? { |marker| content.includes?(marker) }
      end

      roots
    end

    private def application_base_paths_for(file_list : Array(String), quarkus_roots : Set(String)) : Hash(ApplicationBaseKey, String)
      base_paths = Hash(ApplicationBaseKey, String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        next unless quarkus_roots.includes?(project_root_for(path))

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

    private def quarkus_route_source?(content : String) : Bool
      jaxrs_source?(content) ||
        content.includes?("org.jboss.resteasy.reactive") ||
        content.includes?("io.quarkus.vertx.web.Route")
    end

    private def jaxrs_source?(content : String) : Bool
      content.includes?("jakarta.ws.rs") || content.includes?("javax.ws.rs")
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

    private def path_configs_for(file_list : Array(String)) : Hash(String, QuarkusPathConfig)
      configs = Hash(String, QuarkusPathConfig).new
      project_roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        project_roots << project_root_for(path)
      end

      project_roots.each do |root|
        configs[root] = path_config_for(root)
      end

      configs
    end

    private def path_config_for(project_root : String) : QuarkusPathConfig
      values = Hash(String, String).new
      resources = File.join(project_root, "src/main/resources")

      properties_path = File.join(resources, "application.properties")
      values.merge!(read_properties(properties_path)) if File.exists?(properties_path)

      yml_path = File.join(resources, "application.yml")
      yaml_path = File.join(resources, "application.yaml")
      merge_yaml_path_config(values, yml_path) if File.exists?(yml_path)
      merge_yaml_path_config(values, yaml_path) if File.exists?(yaml_path)

      QuarkusPathConfig.new(
        normalize_optional_path(values["quarkus.http.root-path"]?),
        normalize_optional_path(values["quarkus.rest.path"]? || values["quarkus.resteasy.path"]?),
        values["quarkus.http.static-resources.index-page"]? || "index.html"
      )
    end

    private def read_properties(path : String) : Hash(String, String)
      values = Hash(String, String).new
      File.each_line(path) do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("#") || stripped.starts_with?("!")

        if separator = stripped.index(/[=:]/)
          key = stripped[...separator].strip
          value = stripped[(separator + 1)..].strip
          values[key] = value unless key.empty?
        end
      end
      values
    end

    private def merge_yaml_path_config(values : Hash(String, String), path : String)
      if value = yaml_string_value(path, "quarkus", "http", "root-path")
        values["quarkus.http.root-path"] = value
      end
      if value = yaml_string_value(path, "quarkus", "rest", "path")
        values["quarkus.rest.path"] = value
      end
      if value = yaml_string_value(path, "quarkus", "resteasy", "path")
        values["quarkus.resteasy.path"] = value
      end
      if value = yaml_string_value(path, "quarkus", "http", "static-resources", "index-page")
        values["quarkus.http.static-resources.index-page"] = value
      end
    end

    private def yaml_string_value(path : String, *keys : String) : String?
      value = YAML.parse(File.read(path))
      keys.each do |key|
        value = value[key]
      end
      value.as_s?
    rescue
      nil
    end

    private def configured_base_path_for(path : String,
                                         configs : Hash(String, QuarkusPathConfig),
                                         application_base_path : String) : String
      config = configs[project_root_for(path)]? || QuarkusPathConfig.new
      rest_base = application_base_path.empty? ? config.rest_path : application_base_path
      join_paths(config.http_root_path, rest_base)
    end

    private def project_root_for(path : String) : String
      ["/src/main/java/", "/src/"].each do |marker|
        if index = path.index(marker)
          return path[...index]
        end
      end

      configured_base_for(path)
    end

    private def normalize_optional_path(path : String?) : String
      return "" unless path

      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def extract_static_resource_endpoints(project_root : String, config : QuarkusPathConfig) : Array(Endpoint)
      endpoints = [] of Endpoint
      resources_root = File.join(project_root, "src/main/resources/META-INF/resources")
      return endpoints unless Dir.exists?(resources_root)

      Dir.glob(File.join(resources_root, "**", "*")).sort.each do |file|
        next if File.directory?(file)

        relative_path = file[resources_root.size..].lstrip('/')
        next if relative_path.empty?

        details = Details.new(PathInfo.new(file))
        endpoint_path = join_paths(config.http_root_path, "/#{relative_path}")
        endpoints << Endpoint.new(endpoint_path, "GET", details)

        if File.basename(relative_path) == config.static_index_page
          directory = File.dirname(relative_path)
          directory_path = directory == "." ? "/" : "/#{directory}/"
          index_endpoint_path = join_paths(config.http_root_path, directory_path)
          next if endpoints.any? { |endpoint| endpoint.url == index_endpoint_path && endpoint.method == "GET" }

          endpoints << Endpoint.new(index_endpoint_path, "GET", details)
        end
      end

      endpoints
    end

    private struct ReactiveRouteBase
      getter start_offset : Int32
      getter end_offset : Int32
      getter path : String

      def initialize(@start_offset, @end_offset, @path)
      end
    end

    private struct ReactiveMethodCallees
      getter start_byte : Int32
      getter end_byte : Int32
      getter callees : Array(Callee)

      def initialize(@start_byte, @end_byte, @callees)
      end
    end

    private def extract_reactive_route_endpoints(content : String,
                                                 path : String,
                                                 configs : Hash(String, QuarkusPathConfig),
                                                 include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless content.includes?("io.quarkus.vertx.web.Route")

      http_root_path = (configs[project_root_for(path)]? || QuarkusPathConfig.new).http_root_path
      route_bases = reactive_route_bases(content)
      method_callees = include_callee ? reactive_route_method_callees(content, path) : [] of ReactiveMethodCallees

      content.scan(/@Route\b\s*(?:\((.*?)\))?/m) do |match|
        offset = match.begin(0) || 0
        body = match[1]? || ""
        next if reactive_failure_route?(body)

        method_name = route_method_name_after(content, match.end(0) || offset)
        next if method_name.empty?

        route_path = reactive_route_path(body, method_name)
        base_path = route_bases.find { |base| offset >= base.start_offset && offset <= base.end_offset }.try(&.path) || ""
        endpoint_path = join_paths(http_root_path, join_paths(base_path, route_path))
        line = content[0...offset].count('\n') + 1
        details = Details.new(PathInfo.new(path, line))
        params = reactive_route_params(content, match.end(0) || offset, endpoint_path)

        reactive_route_methods(body).each do |method|
          next if endpoints.any? { |endpoint| endpoint.url == endpoint_path && endpoint.method == method }

          endpoint = Endpoint.new(endpoint_path, method, params, details)
          if callees = reactive_method_callees_for(method_callees, content, offset)
            callees.each { |callee| endpoint.push_callee(callee) }
          end
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def reactive_route_method_callees(content : String, path : String) : Array(ReactiveMethodCallees)
      result = [] of ReactiveMethodCallees
      Noir::TreeSitter.parse_java(content) do |root|
        walk_method_declarations(root) do |method|
          body = Noir::TreeSitter.field(method, "body")
          next unless body

          callees = Noir::JavaCalleeExtractor.callees_in_body(body, content, path).map do |(name, callee_path, callee_line)|
            Callee.new(name, path: callee_path, line: callee_line)
          end
          result << ReactiveMethodCallees.new(
            LibTreeSitter.ts_node_start_byte(method).to_i,
            LibTreeSitter.ts_node_end_byte(method).to_i,
            callees
          )
        end
      end
      result
    end

    private def reactive_method_callees_for(method_callees : Array(ReactiveMethodCallees),
                                            content : String,
                                            annotation_offset : Int32) : Array(Callee)?
      annotation_byte = content.char_index_to_byte_index(annotation_offset) || annotation_offset
      method_callees.find do |entry|
        annotation_byte >= entry.start_byte && annotation_byte < entry.end_byte
      end.try(&.callees)
    end

    private def walk_method_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_method_declarations(child, &block)
      end
    end

    private def reactive_failure_route?(annotation_body : String) : Bool
      annotation_body.includes?("HandlerType.FAILURE") ||
        !!annotation_body.match(/\btype\s*=\s*(?:Route\.)?FAILURE\b/)
    end

    private def reactive_route_bases(content : String) : Array(ReactiveRouteBase)
      bases = [] of ReactiveRouteBase
      content.scan(/@RouteBase\b\s*(?:\((.*?)\))?[\s\S]*?\bclass\s+\w+/m) do |match|
        start_offset = match.begin(0) || 0
        class_offset = match.end(0) || start_offset
        open_idx = content.index('{', class_offset)
        next unless open_idx
        close_idx = find_matching_delimiter(content, open_idx, '{', '}') || open_idx
        base_path = reactive_annotation_path(match[1]? || "") || ""
        bases << ReactiveRouteBase.new(start_offset, close_idx, normalize_route_path(base_path))
      end
      bases
    end

    private def reactive_route_path(annotation_body : String, method_name : String) : String
      if path = reactive_annotation_path(annotation_body)
        return normalize_route_path(path)
      end

      normalize_route_path(method_name)
    end

    private def reactive_annotation_path(annotation_body : String) : String?
      body = annotation_body.strip
      if body.starts_with?('"')
        return string_literal_value(body)
      end

      if match = body.match(/(?:path|value)\s*=\s*(["'][^"']+["'])/m)
        string_literal_value(match[1])
      end
    end

    private def reactive_route_methods(annotation_body : String) : Array(String)
      methods = [] of String
      annotation_body.scan(/(?:Route\.)?HttpMethod\.([A-Z]+)/) do |match|
        method = match[1].upcase
        methods << method if HTTP_METHOD_NAMES.includes?(method)
      end

      annotation_body.scan(/\bmethods?\s*=\s*(\{[^}]*\}|[A-Z_][A-Z0-9_]*)/m) do |match|
        match[1].scan(/\b([A-Z]+)\b/) do |method_match|
          method = method_match[1].upcase
          methods << method if HTTP_METHOD_NAMES.includes?(method)
        end
      end

      methods.empty? ? ["GET"] : methods.uniq
    end

    private def route_method_name_after(content : String, offset : Int32) : String
      tail = content[offset..]? || ""
      if match = tail.match(/\A(?:\s|@[A-Za-z0-9_.$]+(?:\([^)]*\))?)*\s*(?:public|protected|private)?\s*(?:static\s+)?(?:[\w.$<>\[\],?]+\s+)+([A-Za-z_][A-Za-z0-9_]*)\s*\(/m)
        match[1]
      else
        ""
      end
    end

    private def reactive_route_params(content : String, offset : Int32, route_path : String) : Array(Param)
      params = [] of Param
      signature = route_method_signature_after(content, offset)
      return params if signature.empty?

      split_top_level_args(signature).each do |arg|
        param_name = parameter_variable_name(arg)
        next if param_name.empty?

        if arg.includes?("@Param")
          name = annotation_string_value(arg, "Param") || param_name
          param_type = route_path.includes?(":#{name}") || route_path.includes?("{#{name}}") ? "path" : "query"
          add_param(params, name, param_type)
        elsif arg.includes?("@Header")
          name = annotation_string_value(arg, "Header") || param_name
          add_param(params, name, "header")
        elsif arg.includes?("@Body")
          add_param(params, param_name, "json")
        end
      end

      params
    end

    private def route_method_signature_after(content : String, offset : Int32) : String
      open_idx = content.index('(', offset)
      return "" unless open_idx
      close_idx = find_matching_delimiter(content, open_idx, '(', ')')
      return "" unless close_idx

      content[(open_idx + 1)...close_idx]
    end

    private def split_top_level_args(source : String) : Array(String)
      args = [] of String
      start = 0
      depth = 0
      in_string = false
      quote = '\0'
      escape = false

      source.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '(', '[', '{', '<'
          depth += 1
        when ')', ']', '}', '>'
          depth -= 1 if depth > 0
        when ','
          next unless depth == 0

          args << source[start...index].strip
          start = index + 1
        end
      end

      tail = source[start..]?.to_s.strip
      args << tail unless tail.empty?
      args
    end

    private def parameter_variable_name(arg : String) : String
      cleaned = arg.gsub(/@\w+(?:\([^)]*\))?/, " ").strip
      if match = cleaned.match(/([A-Za-z_][A-Za-z0-9_]*)\s*(?:=[^=]*)?\z/)
        match[1]
      else
        ""
      end
    end

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). Only `@Param`/`@Header` are probed, so
    # precompile their matchers once at load time.
    ANNOTATION_VALUE_PATTERNS = {
      "Param"  => /@Param\s*\(\s*(?:(?:value|name)\s*=\s*)?(["'][^"']+["'])\s*\)/m,
      "Header" => /@Header\s*\(\s*(?:(?:value|name)\s*=\s*)?(["'][^"']+["'])\s*\)/m,
    }

    private def annotation_string_value(arg : String, annotation_name : String) : String?
      annotation_regex = ANNOTATION_VALUE_PATTERNS[annotation_name]? || /@#{annotation_name}\s*\(\s*(?:(?:value|name)\s*=\s*)?(["'][^"']+["'])\s*\)/m
      if match = arg.match(annotation_regex)
        string_literal_value(match[1])
      end
    end

    private def string_literal_value(expression : String) : String?
      if match = expression.strip.match(/\A["']([^"']*)["']\z/)
        match[1]
      end
    end

    private def normalize_route_path(path : String) : String
      normalized = path.strip
      return "/" if normalized.empty?

      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    private def add_param(params : Array(Param), name : String, param_type : String)
      return if name.empty?
      return if params.any? { |param| param.name == name && param.param_type == param_type }

      params << Param.new(name, "", param_type)
    end

    HTTP_METHOD_NAMES = Set{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE"}

    private def find_matching_delimiter(code : String,
                                        open_idx : Int32,
                                        open_char : Char,
                                        close_char : Char) : Int32?
      # Scan by CHARACTER (not byte): open_idx is a char index from String#index
      # and callers char-slice with / range-compare the returned index. A byte
      # scan corrupts both on multi-byte UTF-8. ASCII-identical.
      depth = 1
      in_string = false
      quote = '\0'
      escape = false

      code.each_char_with_index do |ch, i|
        next if i <= open_idx
        if in_string
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == quote
            in_string = false
          end
        else
          if ch == '"' || ch == '\''
            in_string = true
            quote = ch
          elsif ch == open_char
            depth += 1
          elsif ch == close_char
            depth -= 1
          end
        end
        return i if depth == 0
      end

      nil
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
