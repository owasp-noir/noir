require "../../../models/analyzer"
require "../../../miniparsers/kotlin_route_extractor_ts"
require "../../../miniparsers/kotlin_parameter_extractor_ts"
require "../../../miniparsers/kotlin_callee_extractor"
require "../../engines/kotlin_engine"
require "../../../utils/utils.cr"

module Analyzer::Kotlin
  class Spring < Analyzer
    KOTLIN_EXTENSION = "kt"
    alias SpringRoute = Noir::TreeSitterKotlinRouteExtractor::Route

    private struct SpringPathConfig
      getter servlet_context_path : String
      getter webflux_base_path : String

      def initialize(@servlet_context_path = "", @webflux_base_path = "")
      end

      def web_base_path : String
        @webflux_base_path.empty? ? @servlet_context_path : @webflux_base_path
      end
    end

    SPRING_FRAMEWORK_CALLEE_NAMES = Set{
      "ok", "created", "accepted", "noContent", "notFound", "badRequest",
      "status", "body", "build", "buildAndAwait", "bodyValueAndAwait",
      "linkTo", "methodOn", "println", "toString", "toLong", "toInt",
      "toDouble", "toFloat", "toBoolean", "Integer.parseInt", "Long.parseLong",
      "UUID.fromString", "UUID.randomUUID", "uriBuilder.path", "let", "also", "apply", "run", "with", "listOf",
      "isEmpty", "isNotEmpty", "mutableListOf", "mutableSetOf", "mutableMapOf", "setOf", "mapOf",
      "emptyList", "emptySet", "emptyMap", "compareByDescending", "require", "requireNotNull", "check",
      "checkNotNull",
      "Instant.now", "LocalDate.now", "LocalDateTime.now", "OffsetDateTime.now", "ZonedDateTime.now",
      "SecurityContextHolder.getContext", "Thread.sleep", "Random.nextLong", "ResponseEntity",
      "coroutineScope", "async", "await",
      "incrementAndGet", "getAndIncrement", "delay",
      "Optional.of", "Optional.ofNullable", "Optional.empty",
      "java.util.Optional.of", "java.util.Optional.ofNullable", "java.util.Optional.empty",
    }

    SPRING_FRAMEWORK_CALLEE_PREFIXES = [
      "log.",
      "logger.",
      "req.",
      "request.",
      "response.",
      "ServerResponse.",
      "ResponseEntity.",
      "BodyInserters.",
      "CollectionModel.",
      "URI.",
      "Mono.",
      "Flux.",
    ]

    private struct SpringInterfaceRouteEntry
      getter route : SpringRoute
      getter path : String
      getter source : String
      getter package_name : String

      def initialize(@route, @path, @source, @package_name)
      end
    end

    private struct SpringMethodEntry
      getter path : String
      getter source : String
      getter package_name : String
      getter class_name : String
      getter method_name : String
      getter line : Int32

      def initialize(@path, @source, @package_name, @class_name, @method_name, @line)
      end
    end

    private struct SpringMethodIndex
      getter by_package : Hash(String, Hash(String, Hash(String, Array(SpringMethodEntry))))
      getter by_fqcn : Hash(String, Hash(String, Array(SpringMethodEntry)))
      getter by_supertype : Hash(String, Hash(String, Array(SpringMethodEntry)))
      getter by_supertype_fqcn : Hash(String, Hash(String, Array(SpringMethodEntry)))

      def initialize
        @by_package = Hash(String, Hash(String, Hash(String, Array(SpringMethodEntry)))).new
        @by_fqcn = Hash(String, Hash(String, Array(SpringMethodEntry))).new
        @by_supertype = Hash(String, Hash(String, Array(SpringMethodEntry))).new
        @by_supertype_fqcn = Hash(String, Hash(String, Array(SpringMethodEntry))).new
      end

      def add(package_name : String,
              class_name : String,
              method_name : String,
              entry : SpringMethodEntry,
              supertype_names : Array(String) = [] of String,
              supertype_fqcns : Array(String) = [] of String)
        package_classes = @by_package[package_name] ||= Hash(String, Hash(String, Array(SpringMethodEntry))).new
        class_methods = package_classes[class_name] ||= Hash(String, Array(SpringMethodEntry)).new
        class_methods[method_name] ||= [] of SpringMethodEntry
        class_methods[method_name] << entry

        unless package_name.empty?
          fqcn_methods = @by_fqcn["#{package_name}.#{class_name}"] ||= Hash(String, Array(SpringMethodEntry)).new
          fqcn_methods[method_name] ||= [] of SpringMethodEntry
          fqcn_methods[method_name] << entry
        end

        supertype_names.each do |supertype|
          next if supertype.empty?
          methods = @by_supertype[supertype] ||= Hash(String, Array(SpringMethodEntry)).new
          methods[method_name] ||= [] of SpringMethodEntry
          methods[method_name] << entry
        end

        supertype_fqcns.each do |supertype|
          next if supertype.empty?
          methods = @by_supertype_fqcn[supertype] ||= Hash(String, Array(SpringMethodEntry)).new
          methods[method_name] ||= [] of SpringMethodEntry
          methods[method_name] << entry
        end
      end
    end

    private struct SpringInterfaceRouteIndex
      getter by_package : Hash(String, Hash(String, Array(SpringInterfaceRouteEntry)))
      getter by_fqcn : Hash(String, Array(SpringInterfaceRouteEntry))

      def initialize
        @by_package = Hash(String, Hash(String, Array(SpringInterfaceRouteEntry))).new
        @by_fqcn = Hash(String, Array(SpringInterfaceRouteEntry)).new
      end

      def add(package_name : String, interface_name : String, entry : SpringInterfaceRouteEntry)
        package_routes = @by_package[package_name] ||= Hash(String, Array(SpringInterfaceRouteEntry)).new
        package_routes[interface_name] ||= [] of SpringInterfaceRouteEntry
        package_routes[interface_name] << entry

        unless package_name.empty?
          @by_fqcn["#{package_name}.#{interface_name}"] ||= [] of SpringInterfaceRouteEntry
          @by_fqcn["#{package_name}.#{interface_name}"] << entry
        end
      end
    end

    def analyze
      string_constants_by_base = Hash(String, Hash(String, String)).new do |hash, key|
        hash[key] = Hash(String, String).new
      end
      local_string_constants = Hash(String, Hash(String, String)).new
      dto_builder = Noir::TreeSitterKotlinDtoIndex.new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      functional_router_seen = false

      all_file_list = all_files()
      file_list = spring_kotlin_files(all_file_list)
      src_dirs = spring_src_dirs(all_file_list)
      path_configs = path_configs_for(file_list)
      file_list.each do |path|
        content = read_file_content(path)
        functional_router_seen ||= kotlin_functional_router_file?(content)
        constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(content)
        local_string_constants[path] = constants
        base_constants = string_constants_by_base[configured_base_for(path)]
        constants.each do |name, value|
          base_constants[name] ||= value
        end
      end

      # Resolve `$OTHER_CONST` interpolations now that every file's
      # constants are collected, so a shared `Paths.kt` chain like
      # `const val STATIC_URL = "$PUBLIC_URL/static"` yields `/public/static`.
      # Constants stay scoped per configured base so a monorepo's modules do
      # not leak path constants into one another (#1940).
      string_constants_by_base.each do |base, constants|
        string_constants_by_base[base] = Noir::TreeSitterKotlinRouteExtractor.expand_constant_interpolations(constants)
      end

      # Cross-module indexes (interface inheritance, STOMP destinations)
      # legitimately span build modules, so they resolve against the merged
      # view of every base; in a single-base scan this is just the one map.
      string_constants = merge_string_constants(string_constants_by_base)
      interface_route_index = collect_interface_route_index(file_list, string_constants, local_string_constants)
      method_index = (include_callee || functional_router_seen) ? collect_method_index(file_list) : SpringMethodIndex.new
      stomp_prefixes = stomp_application_prefixes_for(file_list, string_constants, local_string_constants)
      graphql_paths = graphql_paths_for(file_list, path_configs)

      src_dirs.each do |path|
        process_directory(path, path_configs)
      end

      file_list.each do |path|
        project_root = project_root_for(path)
        base_constants = string_constants_by_base[configured_base_for(path)]? || Hash(String, String).new
        process_kotlin_file(
          path, dto_builder, path_configs, base_constants, local_string_constants[path]?,
          interface_route_index, method_index, stomp_prefixes[project_root]? || [""], graphql_paths[project_root]? || "/graphql"
        )
      end

      Fiber.yield
      @result
    end

    # Merge the per-base constant maps into a single lookup for cross-module
    # resolution. First value wins, matching the per-base accumulation order;
    # in the common single-base scan this is a cheap copy of the one map.
    private def merge_string_constants(by_base : Hash(String, Hash(String, String))) : Hash(String, String)
      merged = Hash(String, String).new
      by_base.each_value do |constants|
        constants.each do |name, value|
          merged[name] ||= value
        end
      end
      merged
    end

    private def spring_kotlin_files(files : Array(String)) : Array(String)
      files.select do |path|
        File.exists?(path) &&
          path.ends_with?(".#{KOTLIN_EXTENSION}") &&
          !KotlinEngine.test_path?(path) &&
          !spring_ignored_path?(path)
      end
    end

    private def spring_src_dirs(files : Array(String)) : Array(String)
      dirs = Set(String).new
      files.each do |path|
        next if spring_ignored_path?(path)
        index = path.index("/src/")
        next unless index
        dirs << path[0, index + 4]
      end
      dirs.to_a
    end

    private def spring_ignored_path?(path : String) : Bool
      path.includes?("/.git/") ||
        path.includes?("/.gradle/") ||
        path.includes?("/build/") ||
        path.includes?("/out/") ||
        path.includes?("/target/") ||
        path.includes?("/node_modules/")
    end

    # Read Spring Webflux base-path + static-locations from
    # `application.yml` / `application.properties` so route paths
    # inherit them and static asset directories show up as GET routes.
    private def process_directory(path : String, path_configs : Hash(String, SpringPathConfig))
      return unless path.ends_with?("/src")

      static_locations = [] of String
      project_root = path[0, path.size - 4]
      web_base_path = (path_configs[project_root]? || SpringPathConfig.new).web_base_path

      application_yml_path = File.join(path, "main/resources/application.yml")
      if File.exists?(application_yml_path)
        begin
          config = YAML.parse(File.read(application_yml_path))
          spring = config["spring"]
          if spring
            resources = spring["resources"] || spring["web"]
            if resources
              if resources["resources"]
                resources = resources["resources"]
              end
              static_locations_yaml = resources["static-locations"]
              if static_locations_yaml
                if static_locations_yaml.as_a?
                  static_locations_yaml.as_a.each do |loc|
                    static_locations << loc.as_s
                  end
                elsif static_locations_yaml.as_s?
                  static_locations_yaml.as_s.split(",").each do |loc|
                    static_locations << loc.strip
                  end
                end
              end
            end
          end
        rescue
          # Handle parsing errors if necessary
        end
      end

      application_properties_path = File.join(path, "main/resources/application.properties")
      if File.exists?(application_properties_path)
        begin
          properties = File.read(application_properties_path)
          static_locs = properties.match(/spring(\.web)?\.resources\.static-locations\s*=\s*(.*)/)
          if static_locs
            static_locs[2].split(",").each do |loc|
              static_locations << loc.strip
            end
          end
        rescue
          # Handle parsing errors if necessary
        end
      end

      if static_locations.empty?
        static_locations = ["classpath:/META-INF/resources/", "classpath:/resources/", "classpath:/static/", "classpath:/public/"]
      end

      process_static_locations(path, static_locations, web_base_path)
    end

    private def process_static_locations(src_path : String, static_locations : Array(String), webflux_base_path : String)
      static_locations.each do |location|
        if location.starts_with?("classpath:")
          resource_path = location.sub("classpath:", "").strip
          full_resource_path = File.join(src_path, "main/resources", resource_path)
          if Dir.exists?(full_resource_path)
            Dir.glob("#{escape_glob_path(full_resource_path)}/**/*") do |file|
              next if File.directory?(file)
              relative_path = file.sub(full_resource_path, "")
              full_url = join_path(webflux_base_path, relative_path)
              @result << Endpoint.new(full_url, "GET", Details.new(PathInfo.new(file)))
            end
          end
        elsif location.starts_with?("file:")
          file_path = location.sub("file:", "").strip
          if Dir.exists?(file_path)
            Dir.glob("#{escape_glob_path(file_path)}/**/*") do |file|
              next if File.directory?(file)
              relative_path = file.sub(file_path, "")
              full_url = join_path(webflux_base_path, relative_path)
              @result << Endpoint.new(full_url, "GET", Details.new(PathInfo.new(file)))
            end
          end
        end
      end
    end

    private def collect_interface_route_index(file_list : Array(String),
                                              string_constants : Hash(String, String),
                                              local_string_constants : Hash(String, Hash(String, String))) : SpringInterfaceRouteIndex
      index = SpringInterfaceRouteIndex.new

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?("interface")
        next unless content.includes?("@RequestMapping") || content.includes?("@GetMapping") ||
                    content.includes?("@PostMapping") || content.includes?("@PutMapping") ||
                    content.includes?("@DeleteMapping") || content.includes?("@PatchMapping")

        Noir::TreeSitter.parse_kotlin(content) do |root|
          package_name = Noir::TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          Noir::TreeSitterKotlinRouteExtractor.extract_interface_routes_from(
            root, content, string_constants, local_string_constants[path]?
          ).each do |interface_name, routes|
            routes.each do |route|
              index.add(package_name, interface_name, SpringInterfaceRouteEntry.new(route, path, content, package_name))
            end
          end
        end
      end

      index
    end

    private def collect_method_index(file_list : Array(String)) : SpringMethodIndex
      index = SpringMethodIndex.new

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?("fun") && (content.includes?("class") || content.includes?("object"))

        Noir::TreeSitter.parse_kotlin(content) do |root|
          package_name = Noir::TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          imports = Noir::TreeSitterKotlinParameterExtractor.extract_imports_from(root, content)
          supertypes_by_class = class_supertypes_by_name(root, content, package_name, imports)
          Noir::TreeSitterKotlinParameterExtractor.index_functions_from(root, content).each do |key, node|
            parts = key.split("#", 2)
            next unless parts.size == 2
            class_name = parts[0]
            method_name = parts[1]
            next if class_name.empty? || method_name.empty?

            supertype_fqcns = supertypes_by_class[class_name]? || [] of String
            supertype_names = supertype_fqcns.map(&.split('.').last)
            supertype_names.uniq!
            entry = SpringMethodEntry.new(
              path, content, package_name, class_name, method_name,
              Noir::TreeSitter.node_start_row(node) + 1
            )
            index.add(package_name, class_name, method_name, entry, supertype_names, supertype_fqcns)
          end
        end
      end

      index
    end

    private def class_supertypes_by_name(root : LibTreeSitter::TSNode,
                                         source : String,
                                         package_name : String,
                                         imports : Array(Noir::ImportGraph::ImportRef)) : Hash(String, Array(String))
      results = Hash(String, Array(String)).new
      walk_kotlin_nodes(root) do |node|
        next unless {"class_declaration", "object_declaration"}.includes?(Noir::TreeSitter.node_type(node))
        class_name = kotlin_type_identifier_text(node, source)
        next if class_name.empty?

        supertypes = kotlin_supertype_names(node, source).map do |supertype|
          resolve_kotlin_type_name(supertype, package_name, imports)
        end
        results[class_name] = supertypes.uniq unless supertypes.empty?
      end
      results
    end

    private def kotlin_supertype_names(node : LibTreeSitter::TSNode, source : String) : Array(String)
      names = [] of String
      Noir::TreeSitter.each_named_child(node) do |child|
        next unless Noir::TreeSitter.node_type(child).includes?("delegation")

        # Kotlin represents implemented interfaces as bare `user_type`
        # delegation specifiers. Constructor invocations (`Base()`)
        # are superclass calls and are not useful for DI-interface
        # method expansion here.
        Noir::TreeSitter.each_named_child(child) do |sub|
          next unless Noir::TreeSitter.node_type(sub) == "user_type"
          names << simple_kotlin_type_name(Noir::TreeSitter.node_text(sub, source))
        end
      end
      names.reject!(&.empty?)
      names.uniq!
      names
    end

    private def simple_kotlin_type_name(type_name : String) : String
      type_name
        .gsub(/\s+/, "")
        .split('<').first
        .split('(').first
    end

    private def resolve_kotlin_type_name(type_name : String,
                                         package_name : String,
                                         imports : Array(Noir::ImportGraph::ImportRef)) : String
      return type_name if type_name.includes?(".")

      imports.each do |import_name|
        next if import_name.wildcard?
        return import_name.path if import_name.path.ends_with?(".#{type_name}")
      end

      "#{package_name}.#{type_name}"
    end

    private def visible_interface_routes(index : SpringInterfaceRouteIndex,
                                         package_name : String,
                                         imports : Array(Noir::ImportGraph::ImportRef),
                                         interface_name : String) : Array(SpringInterfaceRouteEntry)
      routes = [] of SpringInterfaceRouteEntry
      seen = Set(String).new

      add_interface_routes(routes, seen, index.by_package[package_name]?.try(&.[interface_name]?))

      imports.each do |import_name|
        path = import_name.path
        if import_name.wildcard?
          add_interface_routes(routes, seen, index.by_package[path]?.try(&.[interface_name]?))
        elsif path.ends_with?(".#{interface_name}")
          add_interface_routes(routes, seen, index.by_fqcn[path]?)
        end
      end

      routes
    end

    private def add_interface_routes(target : Array(SpringInterfaceRouteEntry),
                                     seen : Set(String),
                                     routes : Array(SpringInterfaceRouteEntry)?)
      return unless routes

      routes.each do |entry|
        route = entry.route
        key = "#{entry.path}:#{route.class_name}:#{route.method_name}:#{route.verb}:#{route.path}"
        next if seen.includes?(key)
        seen << key
        target << entry
      end
    end

    private def visible_method_entries(index : SpringMethodIndex,
                                       package_name : String,
                                       imports : Array(Noir::ImportGraph::ImportRef),
                                       class_name : String,
                                       method_name : String) : Array(SpringMethodEntry)
      entries = [] of SpringMethodEntry
      seen = Set(String).new

      add_method_entries(entries, seen, index.by_package[package_name]?.try(&.[class_name]?).try(&.[method_name]?))

      imports.each do |import_name|
        path = import_name.path
        if import_name.wildcard?
          add_method_entries(entries, seen, index.by_package[path]?.try(&.[class_name]?).try(&.[method_name]?))
        elsif path.ends_with?(".#{class_name}")
          add_method_entries(entries, seen, index.by_fqcn[path]?.try(&.[method_name]?))
        end
      end

      if entries.empty?
        add_method_entries(entries, seen, index.by_supertype[resolve_kotlin_type_name(class_name, package_name, imports).split('.').last]?.try(&.[method_name]?))
        imports.each do |import_name|
          path = import_name.path
          if import_name.wildcard?
            add_method_entries(entries, seen, index.by_supertype_fqcn["#{path}.#{class_name}"]?.try(&.[method_name]?))
          elsif path.ends_with?(".#{class_name}")
            add_method_entries(entries, seen, index.by_supertype_fqcn[path]?.try(&.[method_name]?))
          end
        end
      end

      entries
    end

    private def add_method_entries(target : Array(SpringMethodEntry),
                                   seen : Set(String),
                                   entries : Array(SpringMethodEntry)?)
      return unless entries

      entries.each do |entry|
        key = "#{entry.path}:#{entry.class_name}##{entry.method_name}:#{entry.line}"
        next if seen.includes?(key)
        seen << key
        target << entry
      end
    end

    private def stomp_route_file?(content : String) : Bool
      content.includes?("addEndpoint") ||
        content.includes?("@MessageMapping") ||
        content.includes?("@SubscribeMapping")
    end

    private def graphql_route_file?(content : String) : Bool
      content.includes?("@QueryMapping") ||
        content.includes?("@MutationMapping") ||
        content.includes?("@SubscriptionMapping") ||
        content.includes?("@SchemaMapping")
    end

    private def kotlin_functional_router_file?(content : String) : Bool
      content.includes?("coRouter") || content.includes?("router {")
    end

    private def kotlin_spring_route_candidate_file?(content : String) : Bool
      kotlin_spring_mapping_route_file?(content) ||
        stomp_route_file?(content) ||
        graphql_route_file?(content) ||
        kotlin_functional_router_file?(content) ||
        spring_gateway_route_file?(content) ||
        spring_controller_interface_candidate_file?(content)
    end

    private def kotlin_spring_mapping_route_file?(content : String) : Bool
      content.includes?("@RequestMapping") ||
        content.includes?("@GetMapping") ||
        content.includes?("@PostMapping") ||
        content.includes?("@PutMapping") ||
        content.includes?("@DeleteMapping") ||
        content.includes?("@PatchMapping")
    end

    private def spring_gateway_route_file?(content : String) : Bool
      content.includes?("PredicateSpec.") && content.includes?(".path(")
    end

    private def spring_controller_interface_candidate_file?(content : String) : Bool
      content.includes?("RestController") || content.includes?("Controller")
    end

    private def stomp_application_prefixes_for(file_list : Array(String),
                                               string_constants : Hash(String, String),
                                               local_string_constants : Hash(String, Hash(String, String))) : Hash(String, Array(String))
      prefixes = Hash(String, Array(String)).new

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?("setApplicationDestinationPrefixes")

        collected = Noir::TreeSitterKotlinRouteExtractor.extract_stomp_application_prefixes(
          content, string_constants, local_string_constants[path]?
        )
        next if collected.empty?

        root = project_root_for(path)
        prefixes[root] ||= [] of String
        prefixes[root].concat(collected)
        prefixes[root] = prefixes[root].uniq
      end

      prefixes
    end

    private def path_configs_for(file_list : Array(String)) : Hash(String, SpringPathConfig)
      configs = Hash(String, SpringPathConfig).new
      project_roots = Set(String).new

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)
        project_roots << project_root_for(path)
      end

      project_roots.each do |root|
        configs[root] = path_config_for(root)
      end

      configs
    end

    private def path_config_for(project_root : String) : SpringPathConfig
      values = Hash(String, String).new

      resource_dirs_for(project_root).each do |dir|
        properties_path = File.join(dir, "application.properties")
        values.merge!(read_properties(properties_path)) if File.exists?(properties_path)

        yml_path = File.join(dir, "application.yml")
        yaml_path = File.join(dir, "application.yaml")
        merge_yaml_path_config(values, yml_path) if File.exists?(yml_path)
        merge_yaml_path_config(values, yaml_path) if File.exists?(yaml_path)
      end

      SpringPathConfig.new(
        normalize_optional_path(values["server.servlet.context-path"]?),
        normalize_optional_path(values["spring.webflux.base-path"]?)
      )
    end

    private def resource_dirs_for(project_root : String) : Array(String)
      [
        File.join(project_root, "src/main/resources"),
        File.join(project_root, "resources"),
        project_root,
      ].uniq
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
      document = YAML.parse(File.read(path))
      if value = yaml_string_value(document, "server", "servlet", "context-path")
        values["server.servlet.context-path"] = value
      end
      if value = yaml_string_value(document, "spring", "webflux", "base-path")
        values["spring.webflux.base-path"] = value
      end
    rescue
      # Ignore unreadable or malformed YAML.
    end

    private def yaml_string_value(document : YAML::Any, *keys : String) : String?
      value = document
      keys.each do |key|
        value = value[key]
      end
      value.as_s?
    rescue
      nil
    end

    private def normalize_optional_path(path : String?) : String
      return "" unless path

      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def graphql_paths_for(file_list : Array(String), path_configs : Hash(String, SpringPathConfig)) : Hash(String, String)
      paths = Hash(String, String).new
      roots = Set(String).new
      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".#{KOTLIN_EXTENSION}")
        next if KotlinEngine.test_path?(path)
        roots << project_root_for(path)
      end

      roots.each do |root|
        graphql_path = graphql_path_from_resources(root) || "/graphql"
        path_config = path_configs[root]? || SpringPathConfig.new
        paths[root] = join_paths(path_config.web_base_path, graphql_path)
      end

      paths
    end

    private def graphql_path_from_resources(root : String) : String?
      properties_path = File.join(root, "src/main/resources/application.properties")
      if File.exists?(properties_path)
        begin
          File.read(properties_path).each_line do |line|
            if match = line.match(/^\s*spring\.graphql\.path\s*=\s*(\S+)/)
              return normalize_graphql_path(match[1])
            end
          end
        rescue
        end
      end

      yml_path = File.join(root, "src/main/resources/application.yml")
      yaml_path = File.join(root, "src/main/resources/application.yaml")
      [yml_path, yaml_path].each do |path|
        next unless File.exists?(path)
        begin
          config = YAML.parse(File.read(path))
          spring = config["spring"]
          next unless spring
          graphql = spring["graphql"]
          next unless graphql
          configured_path = graphql["path"]
          return normalize_graphql_path(configured_path.as_s) if configured_path
        rescue
        end
      end

      nil
    end

    private def normalize_graphql_path(path : String) : String
      value = path.strip
      value = "/graphql" if value.empty?
      value.starts_with?("/") ? value : "/#{value}"
    end

    private def graphql_params(route : Noir::TreeSitterKotlinRouteExtractor::GraphqlRoute,
                               class_fields : Hash(String, Array(Noir::TreeSitterKotlinParameterExtractor::FieldInfo))) : Array(Param)
      params = [] of Param
      route.arguments.each do |arg|
        type_name = graphql_argument_type_name(arg[:type])
        if fields = class_fields[type_name]?
          fields.each do |field|
            next if field.server_managed?
            push_param_once(params, graphql_input_field_param(field, arg[:name]))
          end
        else
          push_param_once(params, Param.new(arg[:name], "", "json"))
        end
      end

      doc_param_name = "graphql_#{route.operation_keyword}_#{route.field_name}"
      params << Param.new(doc_param_name, graphql_operation_document(route), "json")
      params
    end

    private def graphql_argument_type_name(raw_type : String) : String
      type_name = raw_type.strip
      3.times do
        match = type_name.match(/^(?:[A-Za-z_][A-Za-z0-9_.]*\.)?(?:List|MutableList|Set|MutableSet|Collection|Iterable|Array|Sequence|Flow)\s*<\s*(.+)\s*>\??$/)
        break unless match
        type_name = match[1].strip
      end

      type_name
        .split('.').last
        .gsub(/[^A-Za-z0-9_]/, "")
    end

    private def push_param_once(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def graphql_input_field_param(field : Noir::TreeSitterKotlinParameterExtractor::FieldInfo,
                                          argument_name : String) : Param
      name = argument_name == "input" ? field.name : "#{argument_name}.#{field.name}"
      param = Param.new(name, field.init_value, "json")
      param.add_tag(Tag.new("graphql-input-field", argument_name, "kotlin_spring_graphql_analyzer"))
      param
    end

    private def graphql_operation_document(route : Noir::TreeSitterKotlinRouteExtractor::GraphqlRoute) : String
      if route.operation_keyword == "field"
        if route.arguments.empty?
          "field #{route.root_kind}.#{route.field_name}"
        else
          var_decls = route.arguments.map { |arg| "$#{arg[:name]}: #{arg[:type]}" }.join(", ")
          "field #{route.root_kind}.#{route.field_name}(#{var_decls})"
        end
      elsif route.arguments.empty?
        "#{route.operation_keyword} { #{route.field_name} }"
      else
        var_decls = route.arguments.map { |arg| "$#{arg[:name]}: #{arg[:type]}" }.join(", ")
        call_args = route.arguments.map { |arg| "#{arg[:name]}: $#{arg[:name]}" }.join(", ")
        "#{route.operation_keyword}(#{var_decls}) { #{route.field_name}(#{call_args}) }"
      end
    end

    # Tree-sitter pipeline: route discovery, parameter extraction,
    # `consumes = ...`, and DTO cross-file resolution all run on the
    # vendored Kotlin grammar — no `KotlinParser` / `KotlinLexer`.
    private def process_kotlin_file(path : String,
                                    dto_builder : Noir::TreeSitterKotlinDtoIndex,
                                    path_configs : Hash(String, SpringPathConfig),
                                    string_constants : Hash(String, String),
                                    local_string_constants : Hash(String, String)?,
                                    interface_route_index : SpringInterfaceRouteIndex,
                                    method_index : SpringMethodIndex,
                                    stomp_application_prefixes : Array(String),
                                    graphql_path : String)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      content = read_file_content(path)
      return unless kotlin_spring_route_candidate_file?(content)

      # Single tree-sitter parse for the whole file — every
      # extraction below pulls from the same root so a controller
      # with N routes pays for 1 parse instead of the previous
      # 4 + 2N. Same shape as the Java Spring analyzer's
      # parse-once pipeline.
      Noir::TreeSitter.parse_kotlin(content) do |root|
        # Skip files without a package declaration — legacy filter that
        # avoids scanning test stubs / throwaway snippets.
        package_name = Noir::TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)
        next if package_name.empty?
        imports = Noir::TreeSitterKotlinParameterExtractor.extract_imports_from(root, content)

        project_root = project_root_for(path)
        webflux_base_path = (path_configs[project_root]? || SpringPathConfig.new).web_base_path

        routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes_from(
          root, content, string_constants, local_string_constants
        )
        implementations = Noir::TreeSitterKotlinRouteExtractor.extract_controller_interface_implementations_from(
          root, content, string_constants, local_string_constants
        )
        stomp_routes =
          if stomp_route_file?(content)
            Noir::TreeSitterKotlinRouteExtractor.extract_stomp_routes_from(
              root, content, string_constants, local_string_constants, stomp_application_prefixes
            )
          else
            [] of SpringRoute
          end
        graphql_routes =
          if graphql_route_file?(content)
            Noir::TreeSitterKotlinRouteExtractor.extract_graphql_routes_from(
              root, content, string_constants, local_string_constants
            )
          else
            [] of Noir::TreeSitterKotlinRouteExtractor::GraphqlRoute
          end
        next if routes.empty? && implementations.empty? && stomp_routes.empty? && graphql_routes.empty?

        dto_index = dto_builder.build_for_with_root(path, content, root)
        method_nodes = Noir::TreeSitterKotlinParameterExtractor.index_functions_from(root, content)

        stomp_routes.each do |route|
          route_path = route.verb == "GET" ? join_paths(webflux_base_path, route.path) : route.path
          line = route.line + 1
          key = "#{route.class_name}##{route.method_name}"
          method = method_nodes[key]?
          parameters =
            if method
              Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters_from_method(
                method, content, "POST", "json", dto_index, string_constants, local_string_constants || Hash(String, String).new
              )
            else
              [] of Param
            end
          endpoint = Endpoint.new(route_path, route.verb, parameters, Details.new(PathInfo.new(path, line)))
          endpoint.protocol = "ws"
          route.messaging_destinations.each do |destination|
            endpoint.add_tag(Tag.new("stomp-send-to", destination, "kotlin_spring_stomp_analyzer"))
          end
          attach_method_security_tags(endpoint, method, content)

          if include_callee && !(route.class_name.empty? || route.method_name.empty?)
            before_callee_count = endpoint.callees.size
            attach_method_callees(
              endpoint, root, content, path, route.class_name, route.method_name, line, method_nodes,
              method_index, package_name, imports
            )
            if endpoint.callees.size == before_callee_count
              handler_line = method ? Noir::TreeSitter.node_start_row(method) + 1 : line
              push_spring_callee(endpoint, "#{route.class_name}.#{route.method_name}", path, handler_line)
            end
          end
          if include_callee && route.verb == "GET" && route.class_name.empty? && route.method_name.empty?
            push_spring_callee(endpoint, "StompEndpointRegistry.addEndpoint", path, line)
          end

          @result << endpoint
        end

        graphql_routes.each do |route|
          params = graphql_params(route, dto_index)
          line = route.line + 1
          endpoint = Endpoint.new("#{graphql_path}##{route.root_kind}.#{route.field_name}", "POST", params, Details.new(PathInfo.new(path, line)))
          endpoint.protocol = "ws" if route.root_kind == "Subscription"
          endpoint.add_tag(Tag.new("graphql", "#{route.root_kind}.#{route.field_name}", "kotlin_spring_graphql_analyzer"))
          endpoint.add_tag(Tag.new("graphql-root", route.root_kind, "kotlin_spring_graphql_analyzer"))
          method = method_nodes["#{route.class_name}##{route.method_name}"]?
          attach_method_security_tags(endpoint, method, content)

          if include_callee && !(route.class_name.empty? || route.method_name.empty?)
            before_callee_count = endpoint.callees.size
            attach_method_callees(
              endpoint, root, content, path, route.class_name, route.method_name, line, method_nodes,
              method_index, package_name, imports
            )
            if endpoint.callees.size == before_callee_count
              resolver_line = method ? Noir::TreeSitter.node_start_row(method) + 1 : line
              push_spring_callee(endpoint, "#{route.class_name}.#{route.method_name}", path, resolver_line)
            end
          end

          @result << endpoint
        end

        # Pin the parameter format to the FIRST verb seen for each
        # (class, method) — for multi-verb `@RequestMapping(method =
        # [GET, POST])` we want a single shared format so the
        # `params=` constraint expansion matches across both routes
        # (mirrors the legacy `||=` quirk: first verb wins).
        first_verb = Hash(String, String).new
        routes.each do |route|
          key = "#{route.class_name}##{route.method_name}"
          first_verb[key] ||= route.verb
        end

        routes.each do |route|
          key = "#{route.class_name}##{route.method_name}"
          format_verb = first_verb[key]? || route.verb

          # Pass only the `consumes`-derived format (nil when absent). The
          # verb default (POST → form, others → query) is applied
          # per-parameter inside the extractor so an explicit @RequestBody
          # on a POST resolves to json instead of being dragged to form.
          method = method_nodes[key]?
          parameter_format =
            if method
              Noir::TreeSitterKotlinParameterExtractor.extract_consumes_from_method(method, content)
            else
              Noir::TreeSitterKotlinParameterExtractor.extract_consumes_from(
                root, content, route.class_name, route.method_name
              )
            end

          parameters =
            if method
              Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters_from_method(
                method, content, format_verb, parameter_format, dto_index, string_constants, local_string_constants || Hash(String, String).new
              )
            else
              Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters_from(
                root, content, route.class_name, route.method_name, format_verb, parameter_format, dto_index,
                string_constants, local_string_constants || Hash(String, String).new
              )
            end
          if route.handler_reference && method
            parameters.concat(
              Noir::TreeSitterKotlinParameterExtractor.extract_server_request_parameters_from_method(
                method, content, format_verb, parameter_format, dto_index
              )
            )
          end

          # Drop the trailing `/` on webflux_base_path when the route
          # path already starts with one, so the join doesn't produce
          # `//`.
          base_path = webflux_base_path
          if base_path.ends_with?("/") && route.path.starts_with?("/")
            base_path = base_path[..-2]
          end

          line = route.line + 1
          details = Details.new(PathInfo.new(path, line))
          endpoint = Endpoint.new(join_paths(base_path, route.path), route.verb, parameters, details)
          attach_method_security_tags(endpoint, method, content)

          # Functional router method references can point at a handler
          # class in another file; those are resolved below when callee /
          # AI context enrichment is requested.
          if include_callee && (handler_reference = route.handler_reference)
            endpoint.push_callee(Callee.new(handler_reference, path: path, line: line))
          end
          if include_callee
            before_inline_callee_count = endpoint.callees.size
            route.inline_callees.each do |inline_callee|
              push_spring_callee(endpoint, inline_callee[:name], path, inline_callee[:line])
            end
            if endpoint.callees.size == before_inline_callee_count
              route.inline_callees.each do |inline_callee|
                next unless webflux_response_builder_callee?(inline_callee[:name])

                push_framework_fallback_callee(endpoint, inline_callee[:name], path, inline_callee[:line])
                break
              end
            end
          end

          if include_callee && !(route.class_name.empty? || route.method_name.empty?)
            before_callee_count = endpoint.callees.size
            attach_method_callees(
              endpoint, root, content, path, route.class_name, route.method_name, line, method_nodes,
              method_index, package_name, imports
            )
            if !route.handler_reference && endpoint.callees.size == before_callee_count
              handler_line = method ? Noir::TreeSitter.node_start_row(method) + 1 : line
              push_spring_callee(endpoint, "#{route.class_name}.#{route.method_name}", path, handler_line)
            end
          end
          attach_cross_file_handler_details(
            endpoint, method_index, package_name, imports, path, route, format_verb, parameter_format, dto_builder, include_callee
          ) if route.handler_reference

          @result << endpoint
        end

        # Group inherited interface routes by their interface source so each
        # interface file is parsed (and its DTO index built) once, even when the
        # interface backs several routes or is implemented by multiple
        # controllers, instead of re-parsing it per inherited route.
        interface_work = Hash(String, Array(Tuple(Noir::TreeSitterKotlinRouteExtractor::ControllerInterfaceImplementation, SpringInterfaceRouteEntry))).new
        implementations.each do |implementation|
          implementation.interface_names.each do |interface_name|
            visible_interface_routes(interface_route_index, package_name, imports, interface_name).each do |entry|
              (interface_work[entry.path] ||= [] of Tuple(Noir::TreeSitterKotlinRouteExtractor::ControllerInterfaceImplementation, SpringInterfaceRouteEntry)) << {implementation, entry}
            end
          end
        end

        interface_work.each_value do |pairs|
          interface_source = pairs.first[1].source
          interface_path = pairs.first[1].path

          Noir::TreeSitter.parse_kotlin(interface_source) do |interface_root|
            interface_dto_index = dto_builder.build_for_with_root(interface_path, interface_source, interface_root)

            pairs.each do |implementation, entry|
              entry_route = entry.route
              inherited_path = join_paths(implementation.path, entry_route.path)

              parameter_format = Noir::TreeSitterKotlinParameterExtractor.extract_consumes_from(
                interface_root, interface_source, entry_route.class_name, entry_route.method_name
              )
              parameters = Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters_from(
                interface_root, interface_source, entry_route.class_name, entry_route.method_name,
                entry_route.verb, parameter_format, interface_dto_index,
                string_constants, local_string_constants || Hash(String, String).new
              )

              base_path = webflux_base_path
              if base_path.ends_with?("/") && inherited_path.starts_with?("/")
                base_path = base_path[..-2]
              end

              details = Details.new(PathInfo.new(entry.path, entry_route.line + 1))
              details.add_path(PathInfo.new(path, implementation.line + 1))
              endpoint = Endpoint.new(join_paths(base_path, inherited_path), entry_route.verb, parameters, details)
              attach_method_security_tags(endpoint, method_nodes["#{implementation.class_name}##{entry_route.method_name}"]?, content)

              if include_callee && !(implementation.class_name.empty? || entry_route.method_name.empty?)
                attach_method_callees(
                  endpoint, root, content, path, implementation.class_name, entry_route.method_name, nil, method_nodes,
                  method_index, package_name, imports
                )
              end

              @result << endpoint
            end
          end
        end
      end
    end

    private def attach_method_security_tags(endpoint : Endpoint, method : LibTreeSitter::TSNode?, source : String)
      return unless method

      annotations = spring_security_annotations(method, source)
      return if annotations.empty?

      endpoint.add_tag(Tag.new("auth", "Protected by #{annotations.join("; ")}", "kotlin_spring_security_analyzer"))
    end

    private def spring_security_annotations(method : LibTreeSitter::TSNode, source : String) : Array(String)
      text = Noir::TreeSitter.node_text(method, source)
      annotations = [] of String

      text.scan(/@(PreAuthorize|PostAuthorize)\s*\(\s*"([^"]*)"\s*\)/m) do |match|
        annotations << "@#{match[1]}(#{match[2]})"
      end

      text.scan(/@(Secured|RolesAllowed)\s*\(([^)]*)\)/m) do |match|
        value = match[2].gsub(/\s+/, " ").strip
        annotations << "@#{match[1]}(#{value})"
      end

      annotations.uniq
    end

    private def attach_cross_file_handler_details(endpoint : Endpoint,
                                                  method_index : SpringMethodIndex,
                                                  package_name : String,
                                                  imports : Array(Noir::ImportGraph::ImportRef),
                                                  current_path : String,
                                                  route : SpringRoute,
                                                  verb : String,
                                                  parameter_format : String?,
                                                  dto_builder : Noir::TreeSitterKotlinDtoIndex,
                                                  include_callee : Bool)
      return unless route.handler_reference
      return if route.class_name.empty? || route.method_name.empty?

      entries = visible_method_entries(method_index, package_name, imports, route.class_name, route.method_name)
        .reject { |entry| entry.path == current_path }
      return unless entries.size == 1

      entry = entries.first
      endpoint.details.add_path(PathInfo.new(entry.path, entry.line))

      Noir::TreeSitter.parse_kotlin(entry.source) do |handler_root|
        handler_dto_index = dto_builder.build_for_with_root(entry.path, entry.source, handler_root)
        method_nodes = Noir::TreeSitterKotlinParameterExtractor.index_functions_from(handler_root, entry.source)
        if method = method_nodes["#{entry.class_name}##{entry.method_name}"]?
          Noir::TreeSitterKotlinParameterExtractor.extract_server_request_parameters_from_method(
            method, entry.source, verb, parameter_format, handler_dto_index
          ).each do |param|
            endpoint.push_param(param)
          end
        end

        if include_callee
          handler_imports = Noir::TreeSitterKotlinParameterExtractor.extract_imports_from(handler_root, entry.source)
          attach_method_callees(
            endpoint, handler_root, entry.source, entry.path, entry.class_name, entry.method_name, entry.line, method_nodes,
            method_index, entry.package_name, handler_imports
          )
        end
      end
    rescue e
      @logger.debug "Failed to resolve Kotlin Spring functional handler #{route.class_name}##{route.method_name}: #{e.message}"
    end

    private def attach_method_callees(endpoint : Endpoint,
                                      root : LibTreeSitter::TSNode,
                                      source : String,
                                      path : String,
                                      class_name : String,
                                      method_name : String,
                                      route_line : Int32?,
                                      method_nodes : Hash(String, LibTreeSitter::TSNode),
                                      method_index : SpringMethodIndex? = nil,
                                      package_name : String = "",
                                      imports : Array(Noir::ImportGraph::ImportRef) = [] of Noir::ImportGraph::ImportRef,
                                      expansion_depth : Int32 = 0,
                                      expansion_seen : Set(String)? = nil)
      direct_entries = Noir::KotlinCalleeExtractor.callees_in_method(
        root, source, path, class_name, method_name, route_line
      )
      expansion_entries = [] of Tuple(String, String, Int32)
      direct_entries.each do |entry|
        name, callee_path, callee_line = entry
        push_spring_callee(endpoint, name, callee_path, callee_line)
        expansion_entries << entry
      end

      expanded_helpers = Set(String).new
      direct_entries.each do |entry|
        helper_name = entry[0]
        next unless same_class_helper_callee?(helper_name)
        next unless expanded_helpers.add?(helper_name)
        helper_key = "#{class_name}##{helper_name}"
        helper_node = method_nodes[helper_key]?
        next unless helper_node

        helper_line = Noir::TreeSitter.node_start_row(helper_node) + 1
        add_code_path_once(endpoint, path, helper_line)
        Noir::KotlinCalleeExtractor.callees_in_method(
          root, source, path, class_name, helper_name, helper_line
        ).each do |helper_entry|
          name, callee_path, callee_line = helper_entry
          push_spring_callee(endpoint, name, callee_path, callee_line)
          expansion_entries << helper_entry
        end
      end

      expand_injected_receiver_callees(
        endpoint, method_index, package_name, imports, root, source, class_name, expansion_entries,
        expansion_depth, expansion_seen || Set(String).new
      )
    end

    private def expand_injected_receiver_callees(endpoint : Endpoint,
                                                 method_index : SpringMethodIndex?,
                                                 package_name : String,
                                                 imports : Array(Noir::ImportGraph::ImportRef),
                                                 root : LibTreeSitter::TSNode,
                                                 source : String,
                                                 class_name : String,
                                                 entries : Array(Tuple(String, String, Int32)),
                                                 expansion_depth : Int32,
                                                 expansion_seen : Set(String))
      return unless method_index
      return if expansion_depth >= 2

      receiver_types = constructor_injected_receiver_types(root, source, class_name)
      return if receiver_types.empty?

      entries.each do |entry|
        callee_name = entry[0]
        match = callee_name.match(/^([a-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)$/)
        next unless match

        receiver = match[1]
        method_name = match[2]
        receiver_type = receiver_types[receiver]?
        next unless receiver_type

        resolved_entries = visible_method_entries(method_index, package_name, imports, receiver_type, method_name)
        resolved = unique_method_entry_for_path(resolved_entries, entry[1])
        next unless resolved

        seen_key = "#{resolved.path}:#{resolved.class_name}##{resolved.method_name}:#{resolved.line}"
        next unless expansion_seen.add?(seen_key)

        add_code_path_once(endpoint, resolved.path, resolved.line)
        Noir::TreeSitter.parse_kotlin(resolved.source) do |resolved_root|
          resolved_imports = Noir::TreeSitterKotlinParameterExtractor.extract_imports_from(resolved_root, resolved.source)
          resolved_method_nodes = Noir::TreeSitterKotlinParameterExtractor.index_functions_from(resolved_root, resolved.source)
          attach_method_callees(
            endpoint, resolved_root, resolved.source, resolved.path, resolved.class_name, resolved.method_name,
            resolved.line, resolved_method_nodes, method_index, resolved.package_name, resolved_imports,
            expansion_depth + 1, expansion_seen
          )
        end
      end
    end

    private def unique_method_entry_for_path(entries : Array(SpringMethodEntry), current_path : String) : SpringMethodEntry?
      return entries.first if entries.size == 1

      current_root = project_root_for(current_path)
      scoped_entries = entries.select { |entry| project_root_for(entry.path) == current_root }
      return scoped_entries.first if scoped_entries.size == 1

      nil
    end

    private def constructor_injected_receiver_types(root : LibTreeSitter::TSNode,
                                                    source : String,
                                                    class_name : String) : Hash(String, String)
      types = Hash(String, String).new
      walk_kotlin_nodes(root) do |node|
        next unless {"class_declaration", "object_declaration"}.includes?(Noir::TreeSitter.node_type(node))
        next unless kotlin_type_identifier_text(node, source) == class_name

        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "primary_constructor"
          Noir::TreeSitter.each_named_child(child) do |param|
            next unless Noir::TreeSitter.node_type(param) == "class_parameter"
            text = Noir::TreeSitter.node_text(param, source)
            if match = text.match(/\b(?:val|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)/)
              types[match[1]] = match[2].split('.').last
            end
          end
        end
      end
      types
    end

    private def walk_kotlin_nodes(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_kotlin_nodes(child, &block)
      end
    end

    private def kotlin_type_identifier_text(decl : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(decl) do |child|
        if Noir::TreeSitter.node_type(child) == "type_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      ""
    end

    private def same_class_helper_callee?(name : String) : Bool
      return false if name.includes?(".") || name.includes?("::")
      return false if spring_framework_callee?(name)
      !!name.match(/^[a-z_][A-Za-z0-9_]*$/)
    end

    # Same-class private helpers whose names denote a pure local transform or
    # thin wrapper (`filterBy…`, `sortBy…`, `withDetails`). They carry no review
    # signal of their own — the analyzer already expands into their body and
    # surfaces the deeper callees — so suppress the bare helper name itself.
    private def same_class_low_signal_helper_callee?(name : String) : Bool
      return false if name.includes?(".")
      !!name.match(/^(?:filter|sort|with)[A-Z]/)
    end

    private def add_code_path_once(endpoint : Endpoint, path : String, line : Int32)
      return if endpoint.details.code_paths.any? { |code_path| code_path.path == path && code_path.line == line }
      endpoint.details.add_path(PathInfo.new(path, line))
    end

    private def push_spring_callee(endpoint : Endpoint, name : String, path : String, line : Int32)
      if expiry_validation_callee?(name)
        add_code_path_once(endpoint, path, line)
        return
      end
      return if same_class_low_signal_helper_callee?(name)
      return if spring_framework_callee?(name, endpoint.method)
      callee = Callee.new(name, path: path, line: line)
      return if endpoint.callees.any? { |existing| existing == callee }
      return if duplicate_spring_callee?(endpoint, callee)
      if endpoint.callees.size >= Callee::MAX_PER_ENDPOINT
        if replace_index = lower_priority_callee_index(endpoint.callees, callee)
          endpoint.callees[replace_index] = callee
        end
        return
      end
      endpoint.callees << callee
    end

    private def push_framework_fallback_callee(endpoint : Endpoint, name : String, path : String, line : Int32)
      callee = Callee.new(name, path: path, line: line)
      return if endpoint.callees.any? { |existing| existing == callee }
      endpoint.callees << callee
    end

    private def webflux_response_builder_callee?(name : String) : Bool
      name.matches?(/^ServerResponse\.(?:ok|created|accepted|noContent|notFound|badRequest|status)$/)
    end

    private def duplicate_spring_callee?(endpoint : Endpoint, callee : Callee) : Bool
      return false if uri_sensitive_callee?(callee.name)

      endpoint.callees.any? do |existing|
        existing.name == callee.name && existing.path == callee.path
      end
    end

    private def uri_sensitive_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2].downcase
      leaf = parts.last.downcase
      return true if receiver.ends_with?("client") || receiver.ends_with?("template") || receiver.ends_with?("gateway")

      {"get", "post", "put", "patch", "delete"}.includes?(leaf)
    end

    private def lower_priority_callee_index(existing : Array(Callee), incoming : Callee) : Int32?
      incoming_priority = spring_callee_priority(incoming.name)
      candidate = nil
      candidate_priority = incoming_priority

      existing.each_with_index do |callee, index|
        priority = spring_callee_priority(callee.name)
        next unless priority <= 45
        next unless priority < candidate_priority

        candidate = index
        candidate_priority = priority
      end

      candidate
    end

    private def spring_callee_priority(name : String) : Int32
      parts = name.split('.')
      receiver = parts.size > 1 ? parts[-2].downcase : ""
      leaf = parts.last
      normalized_leaf = leaf.downcase

      return 95 if normalized_leaf.matches?(/^(save|delete|deletebyid|remove|revoke|revokeall|revokeallusertokens|rotate|update|create|send|generate|encode|matches)$/)
      return 92 if normalized_leaf.starts_with?("save") || normalized_leaf.starts_with?("delete") || normalized_leaf.starts_with?("revoke")
      return 90 if normalized_leaf.starts_with?("create") || normalized_leaf.starts_with?("generate") || normalized_leaf.starts_with?("rotate")
      return 88 if receiver.includes?("passwordencoder") || name.includes?("PasswordEncoder")
      return 86 if receiver.ends_with?("service")
      return 84 if receiver.ends_with?("client") || receiver.ends_with?("template") || receiver.ends_with?("gateway")
      return 82 if parts.size == 1 && normalized_leaf.matches?(/^(extract|add|delete|get|create|generate|validate|verify)/)
      return 78 if normalized_leaf.matches?(/^(validate|verify|exists|existsbyid|isbefore|isafter)$/)
      return 78 if normalized_leaf.starts_with?("validate") || normalized_leaf.starts_with?("verify")
      return 72 if normalized_leaf.starts_with?("findby") || normalized_leaf.starts_with?("exists")
      return 45 if normalized_leaf.starts_with?("findall") || normalized_leaf.starts_with?("getall")

      60
    end

    private def spring_framework_callee?(name : String, endpoint_method : String? = nil) : Bool
      return false if name.includes?("::")
      return true if SPRING_FRAMEWORK_CALLEE_NAMES.includes?(name)

      leaf = name.split('.').last
      return true if SPRING_FRAMEWORK_CALLEE_NAMES.includes?(leaf)
      return true if name == leaf && leaf.ends_with?("Exception")
      return true if name == leaf && !!leaf.match(/^[A-Z][A-Za-z0-9_]*$/)
      return true if response_wrapper_callee?(name)
      return true if domain_factory_callee?(name)
      return true if kotlin_data_copy_callee?(name)
      return true if presentation_callee?(name)
      return true if higher_order_parameter_callee?(name)
      return true if query_dsl_builder_callee?(name)
      return true if random_generator_callee?(name)
      return true if expiry_validation_callee?(name)
      return true if collection_transform_callee?(name, state_changing_endpoint_method?(endpoint_method))
      return true if kotlin_string_utility_callee?(name)
      return true if optional_unwrap_callee?(name)
      return true if optional_wrapper_transform_callee?(name)
      return true if token_config_getter_callee?(name)

      SPRING_FRAMEWORK_CALLEE_PREFIXES.any? { |prefix| name.starts_with?(prefix) }
    end

    private def response_wrapper_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts.first
      leaf = parts.last
      (receiver.ends_with?("Response") || receiver.ends_with?("ResponseDto")) &&
        !!leaf.match(/^(build|create|from|of|ok|success|error)/i)
    end

    private def domain_factory_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless receiver.matches?(/^[A-Z][A-Za-z0-9_]*$/)
      return false if business_callee_receiver?(receiver)

      {"create", "of", "from", "build", "new"}.includes?(leaf)
    end

    private def kotlin_data_copy_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2 || parts.last != "copy"

      receiver = parts[-2]
      !business_callee_receiver?(receiver)
    end

    private def presentation_callee?(name : String) : Bool
      return true if response_projection_callee?(name)

      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return true if receiver == "model" && leaf == "addAttribute"

      leaf == "add" && {"resource", "resources", "entityModel", "collectionModel", "links"}.includes?(receiver)
    end

    private def response_projection_callee?(name : String) : Bool
      parts = name.split('.')
      leaf = parts.last
      return true if parts.size == 1 && !!leaf.match(/^mapTo(Dto|Response)$/i)
      return false if parts.size < 2

      receiver = parts[-2]
      return true if !!leaf.match(/^(to|from)(Dto|Domain|Entity)$/i) && !business_callee_receiver?(receiver)
      return true if receiver.ends_with?("Resource") && !!leaf.match(/^from(Dto|Domain|Entity)?$/i)
      return true if receiver.ends_with?("Dto") && !!leaf.match(/^(to|from)(Dto|Domain|Entity)$/i)
      return true if receiver.ends_with?("Entity") && !!leaf.match(/^(to|from)(Dto|Domain)$/i)
      return true if receiver.ends_with?("Mapper") && !!leaf.match(/^(to|from)(Dto|Domain|Entity|Response)$/i)

      false
    end

    private def higher_order_parameter_callee?(name : String) : Bool
      name == "mapping"
    end

    private def query_dsl_builder_callee?(name : String) : Bool
      return true if {"node", "match", "literalOf", "where", "count", "query"}.includes?(name)

      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      leaf == "property" && receiver.downcase.starts_with?("node")
    end

    private def random_generator_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless {"nextInt", "nextLong", "nextDouble", "nextFloat", "nextBoolean", "nextBytes"}.includes?(leaf)

      normalized = receiver.downcase
      normalized == "random" || normalized.ends_with?("random")
    end

    private def expiry_validation_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless {"isBefore", "isAfter"}.includes?(leaf)

      !!receiver.match(/(?:expiry|expires?|expired|validUntil|notAfter)/i)
    end

    private def optional_unwrap_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2 || parts.last != "get"

      receiver = parts[-2]
      !business_callee_receiver?(receiver)
    end

    private def optional_wrapper_transform_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless {"map", "flatMap", "filter", "orElse", "orElseGet", "orElseThrow", "ifPresent"}.includes?(leaf)
      return false if business_callee_receiver?(receiver)

      normalized = receiver.downcase
      normalized.starts_with?("optional") ||
        normalized.starts_with?("maybe") ||
        normalized.starts_with?("nullable") ||
        normalized.starts_with?("existing")
    end

    private def token_config_getter_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2].downcase
      leaf = parts.last
      return false unless receiver.includes?("jwt") || receiver.includes?("token")

      !!leaf.match(/^get.*(?:CookieName|ExpirationTime)$/)
    end

    private def collection_transform_callee?(name : String, preserve_domain_mutation : Bool = false) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless {
                            "map", "mapNotNull", "flatMap", "filter", "filterNotNull", "forEach",
                            "sortedWith", "distinctBy", "maxByOrNull", "minByOrNull", "indexOfFirst",
                            "toMutableList", "toMutableSet", "toList",
                            "toSet", "asFlow", "find", "first", "firstOrNull", "last", "lastOrNull",
                            "single", "singleOrNull", "none", "add", "addAll", "remove", "removeAll", "removeIf", "clear",
                          }.includes?(leaf)
      return false if business_callee_receiver?(receiver)
      return false if preserve_domain_mutation && domain_collection_mutation_callee?(receiver, leaf)

      # Plural/collection-shaped receivers (`results`, `items`, `tags`, …) are
      # all covered by the trailing-`s`/`list` checks; only the singular
      # `result` needs to be named explicitly.
      normalized = receiver.downcase
      normalized == "result" ||
        normalized.ends_with?("s") ||
        normalized.ends_with?("list")
    end

    private def domain_collection_mutation_callee?(receiver : String, leaf : String) : Bool
      return false unless {"add", "addAll", "remove", "removeAll", "removeIf", "clear"}.includes?(leaf)

      normalized = receiver.downcase
      return false if normalized.starts_with?("new") || normalized.starts_with?("pending") || normalized.starts_with?("temp")
      return false if {"result", "results", "items", "entities", "dtos", "roles", "tags", "cookies"}.includes?(normalized)

      normalized.ends_with?("s") || normalized.ends_with?("list")
    end

    private def state_changing_endpoint_method?(method : String?) : Bool
      return false unless method

      {"POST", "PUT", "PATCH", "DELETE"}.includes?(method.upcase)
    end

    private def kotlin_string_utility_callee?(name : String) : Bool
      parts = name.split('.')
      return false if parts.size < 2

      receiver = parts[-2]
      leaf = parts.last
      return false unless {"isBlank", "isNullOrBlank", "lowercase", "uppercase", "trim"}.includes?(leaf)

      !business_callee_receiver?(receiver)
    end

    private def business_callee_receiver?(receiver : String) : Bool
      normalized = receiver.downcase
      {"service", "repository", "repo", "client", "template", "gateway", "dao", "mapper"}.any? do |suffix|
        normalized.ends_with?(suffix)
      end
    end

    private def project_root_for(path : String) : String
      ["/src/main/kotlin/", "/src/"].each do |marker|
        if index = path.index(marker)
          return path[...index]
        end
      end

      File.dirname(path)
    end
  end
end
