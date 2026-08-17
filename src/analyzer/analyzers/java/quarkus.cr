require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"
require "yaml"
require "../../../utils/url_path"
require "../../../utils/top_level_split"

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
    analyzer_for "java_quarkus"

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
      include_callee = callees_needed?
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new
      custom_verb_cache = Hash(String, Hash(String, String)).new

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
        next if JavaEngine.test_path?(base_relative_path(path))
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
          custom_verb_annotations = custom_verb_index_for(path, content, package_name, custom_verb_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_custom_verb_annotations_from(root, content))
          application_base_path = application_base_path_for(path, package_name, application_base_paths)
          configured_base_path = configured_base_path_for(path, path_configs, application_base_path)

          extract_reactive_route_endpoints(content, path, path_configs, include_callee).each do |endpoint|
            @result << endpoint
          end

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources,
            custom_verb_annotations: custom_verb_annotations, include_callees: include_callee).each do |route|
            line = route.line + 1
            details = Details.new(PathInfo.new(route.file_path || path, line))
            endpoint = Endpoint.new(Noir::URLPath.join_trimmed(configured_base_path, route.path), route.verb, route.params, details)
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
        next if JavaEngine.test_path?(base_relative_path(path))
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
        next if JavaEngine.test_path?(base_relative_path(path))
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

    # `quarkus_route_source?`/`jaxrs_source?` gate per-file tree-sitter
    # parses; one precompiled `Regex.union` scan (PCRE2 JIT, auto-escapes
    # each literal) each replaces the chained `String#includes?` passes
    # over the same buffer.
    JAXRS_SOURCE_RE         = Regex.union("jakarta.ws.rs", "javax.ws.rs")
    QUARKUS_ROUTE_SOURCE_RE = Regex.union(
      "jakarta.ws.rs", "javax.ws.rs", "org.jboss.resteasy.reactive", "io.quarkus.vertx.web.Route"
    )

    private def quarkus_route_source?(content : String) : Bool
      content.matches?(QUARKUS_ROUTE_SOURCE_RE)
    end

    private def jaxrs_source?(content : String) : Bool
      content.matches?(JAXRS_SOURCE_RE)
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

    private def path_configs_for(file_list : Array(String)) : Hash(String, QuarkusPathConfig)
      configs = Hash(String, QuarkusPathConfig).new
      project_roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
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
      read_file_content(path).each_line do |line|
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
      value = YAML.parse(read_file_content(path))
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
      Noir::URLPath.join_trimmed(config.http_root_path, rest_base)
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

      # `Dir.glob` rather than a `file_map` lookup: the endpoint set is
      # "every file Quarkus serves out of META-INF/resources", including
      # the images and fonts the media filter keeps out of the index. That
      # also means `--exclude-path` never reached this walk, so it is
      # applied per file here.
      Dir.glob(File.join(resources_root, "**", "*")).sort.each do |file|
        next if File.directory?(file)
        next if excluded_path?(file)

        relative_path = file[resources_root.size..].lstrip('/')
        next if relative_path.empty?

        details = Details.new(PathInfo.new(file))
        endpoint_path = Noir::URLPath.join_trimmed(config.http_root_path, "/#{relative_path}")
        endpoints << Endpoint.new(endpoint_path, "GET", details)

        if File.basename(relative_path) == config.static_index_page
          directory = File.dirname(relative_path)
          directory_path = directory == "." ? "/" : "/#{directory}/"
          index_endpoint_path = Noir::URLPath.join_trimmed(config.http_root_path, directory_path)
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

      each_reactive_route_annotation(content) do |offset, end_offset, body|
        next if reactive_failure_route?(body)

        method_name = route_method_name_after(content, end_offset)
        next if method_name.empty?

        route_path = reactive_route_path(body, method_name)
        next if route_path.nil?

        base_path = route_bases.find { |base| offset >= base.start_offset && offset <= base.end_offset }.try(&.path) || ""
        endpoint_path = Noir::URLPath.join_trimmed(http_root_path, Noir::URLPath.join_trimmed(base_path, route_path))
        line = content[0...offset].count('\n') + 1
        details = Details.new(PathInfo.new(path, line))
        params = reactive_route_params(content, end_offset, endpoint_path)

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

    # Locate each `@Route` annotation with a delimiter-balanced argument
    # scan so values containing `)` (common in `regex=` capture groups)
    # do not truncate the body. Skips `@RouteBase` via a word-boundary
    # check after the `@Route` prefix.
    private def each_reactive_route_annotation(content : String, & : Int32, Int32, String ->)
      offset = 0
      while idx = content.index("@Route", offset)
        name_end = idx + 6 # length of "@Route"
        if name_end < content.size && (content[name_end].alphanumeric? || content[name_end] == '_')
          # Longer annotation name (`@RouteBase`, `@RouteFilter`, …).
          offset = name_end
        else
          cursor = name_end
          while cursor < content.size && content[cursor].ascii_whitespace?
            cursor += 1
          end

          if cursor < content.size && content[cursor] == '('
            if close_idx = JavaEngine.find_matching_delimiter(content, cursor, '(', ')')
              end_offset = close_idx + 1
              yield idx, end_offset, content[(cursor + 1)...close_idx]
              offset = end_offset
            else
              # Unbalanced `(` — skip past it without yielding.
              offset = cursor + 1
            end
          else
            # Bare `@Route` with no argument list.
            yield idx, cursor, ""
            offset = cursor
          end
        end
      end
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
        close_idx = JavaEngine.find_matching_delimiter(content, open_idx, '{', '}') || open_idx
        base_path = reactive_annotation_path(match[1]? || "") || ""
        bases << ReactiveRouteBase.new(start_offset, close_idx, normalize_route_path(base_path))
      end
      bases
    end

    # Resolve the route path for a `@Route` annotation. Explicit
    # `path=`/`value=` wins. When only `regex=` is set, Quarkus
    # registers via `routeWithRegex` and never derives a method-name
    # path — surface the regex pattern itself (or nil if unreadable)
    # rather than inventing a literal path. With neither path nor
    # regex, fall back to Quarkus's dashify of the method name.
    private def reactive_route_path(annotation_body : String, method_name : String) : String?
      if path = reactive_annotation_path(annotation_body)
        return normalize_route_path(path)
      end

      if regex = reactive_annotation_regex(annotation_body)
        # Surface the pattern as-is (may start with escapes like `\/…`,
        # not a filesystem-style path that needs a leading `/`).
        return regex
      end

      # Bare `regex=` with an unreadable value must not fall through
      # to the method-name path — Quarkus never registers that path.
      return if annotation_body.match(/\bregex\s*=/)

      normalize_route_path(dashify(method_name))
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

    private def reactive_annotation_regex(annotation_body : String) : String?
      if match = annotation_body.match(/\bregex\s*=\s*(["'][^"']+["'])/m)
        string_literal_value(match[1])
      end
    end

    # Quarkus `ReactiveRoutesProcessor.dashify`: insert '-' before any
    # interior (not first/last) uppercase char and lower-case every
    # char. `getItemList` → `get-item-list`.
    private def dashify(name : String) : String
      return name if name.empty?

      String.build do |io|
        last = name.size - 1
        name.each_char_with_index do |char, index|
          if index > 0 && index < last && char.ascii_uppercase?
            io << '-'
          end
          io << char.downcase
        end
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
      close_idx = JavaEngine.find_matching_delimiter(content, open_idx, '(', ')')
      return "" unless close_idx

      content[(open_idx + 1)...close_idx]
    end

    # `Rules::JAVA` plus `Nest::Angle`, on the same shared depth counter. Not
    # the shared `Rules::JAVA` preset: this splitter runs on a JAX-RS resource
    # method's parameter list, where `Map<String, List<Integer>>` is one
    # parameter and must not break in two. The cost is that a `<` used as a
    # comparison — `f(a < b, c)` — raises the depth and swallows the comma,
    # which cannot happen in a parameter list. File-local because quarkus is
    # the only splitter with exactly this combination; wicket also counts
    # angles but takes only `"` as a quote.
    SPLIT_ARGS_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace | Noir::TopLevelSplit::Nest::Angle,
      quotes: "\"'",
      escape: Noir::TopLevelSplit::Escape::InQuotes,
      strip: true,
      empties: Noir::TopLevelSplit::Empties::DropTrailing,
      per_kind: false,
      clamp: true,
    )

    private def split_top_level_args(source : String) : Array(String)
      Noir::TopLevelSplit.split(source, ',', SPLIT_ARGS_RULES)
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

    # Build the cross-file `@HttpMethod("VERB")` custom-annotation
    # index for `path`. Same traversal as `bean_index_for` — the
    # annotation type is typically declared in its own file, so this
    # needs the same current file + same-package siblings + imports
    # walk, gated on the file mentioning JAX-RS so unrelated `.java`
    # files aren't parsed for annotation declarations.
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
            if body.includes?("jakarta.ws.rs") || body.includes?("javax.ws.rs")
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
