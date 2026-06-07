require "../../../models/analyzer"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../miniparsers/java_parameter_extractor_ts"
require "../../../miniparsers/java_callee_extractor"
require "../../engines/java_engine"
require "yaml"

module Analyzer::Java
  class Spring < Analyzer
    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    REGEX_ROUTE_CALL        = /((?:andRoute|route)\s*\(|\.)\s*(?:RequestPredicates\.)?(GET|POST|DELETE|PUT|PATCH|HEAD|OPTIONS)\s*\(/

    alias SpringRouteMapping = Noir::TreeSitterJavaRouteExtractor::ClassMapping
    alias SpringRoute = Noir::TreeSitterJavaRouteExtractor::Route
    alias PackageScopeKey = Tuple(String, String)

    private struct SpringPathConfig
      getter servlet_context_path : String
      getter webflux_base_path : String

      def initialize(@servlet_context_path = "", @webflux_base_path = "")
      end

      def web_base_path : String
        @webflux_base_path.empty? ? @servlet_context_path : @webflux_base_path
      end
    end

    private struct SpringMetaAnnotationIndex
      getter by_package : Hash(PackageScopeKey, Hash(String, SpringRouteMapping))
      getter by_fqcn : Hash(PackageScopeKey, SpringRouteMapping)

      def initialize
        @by_package = Hash(PackageScopeKey, Hash(String, SpringRouteMapping)).new
        @by_fqcn = Hash(PackageScopeKey, SpringRouteMapping).new
      end

      def add(project_root : String, package_name : String, annotation_name : String, mapping : SpringRouteMapping)
        package_mappings = @by_package[{project_root, package_name}] ||= Hash(String, SpringRouteMapping).new
        package_mappings[annotation_name] = mapping

        unless package_name.empty?
          @by_fqcn[{project_root, "#{package_name}.#{annotation_name}"}] = mapping
        end
      end
    end

    private struct SpringInterfaceRouteEntry
      getter route : SpringRoute
      getter path : String
      getter source : String
      getter package_name : String

      def initialize(@route, @path, @source, @package_name)
      end
    end

    private struct SpringInterfaceRouteIndex
      getter by_package : Hash(PackageScopeKey, Hash(String, Array(SpringInterfaceRouteEntry)))
      getter by_fqcn : Hash(PackageScopeKey, Array(SpringInterfaceRouteEntry))

      def initialize
        @by_package = Hash(PackageScopeKey, Hash(String, Array(SpringInterfaceRouteEntry))).new
        @by_fqcn = Hash(PackageScopeKey, Array(SpringInterfaceRouteEntry)).new
      end

      def add(project_root : String, package_name : String, interface_name : String, entry : SpringInterfaceRouteEntry)
        package_routes = @by_package[{project_root, package_name}] ||= Hash(String, Array(SpringInterfaceRouteEntry)).new
        package_routes[interface_name] ||= [] of SpringInterfaceRouteEntry
        package_routes[interface_name] << entry

        unless package_name.empty?
          key = {project_root, "#{package_name}.#{interface_name}"}
          @by_fqcn[key] ||= [] of SpringInterfaceRouteEntry
          @by_fqcn[key] << entry
        end
      end
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      webflux_base_path_map = Hash(String, String).new
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      file_list = all_files()
      path_configs = path_configs_for(file_list)
      stomp_prefixes = stomp_application_prefixes_for(file_list)
      meta_annotation_index = collect_meta_annotation_index(file_list)
      interface_route_index = collect_interface_route_index(file_list, meta_annotation_index)
      file_list.each do |path|
        # Extract the Webflux base path from 'application.yml' /
        # 'application.properties' so route paths inherit it.
        if File.directory?(path)
          if path.ends_with?("/src")
            application_yml_path = File.join(path, "main/resources/application.yml")
            if File.exists?(application_yml_path)
              begin
                config = YAML.parse(File.read(application_yml_path))
                spring = config["spring"]
                webflux = spring["webflux"]
                webflux_base_path = webflux["base-path"]

                if webflux_base_path
                  webflux_base_path_map[path] = webflux_base_path.as_s
                end
              rescue
                # Handle parsing errors if necessary
              end
            end

            application_properties_path = File.join(path, "main/resources/application.properties")
            if File.exists?(application_properties_path)
              begin
                properties = File.read(application_properties_path)
                base_path = properties.match(/spring\.webflux\.base-path\s*=\s*(.*)/)
                if base_path
                  webflux_base_path = base_path[1]
                  webflux_base_path_map[path] = webflux_base_path if webflux_base_path
                end
              rescue
                # Handle parsing errors if necessary
              end
            end
          end
        elsif File.exists?(path) && path.ends_with?(".java")
          # Skip Maven/Gradle test sources via the shared
          # `JavaEngine.test_path?` helper; see the helper doc for
          # the rationale (`src/test/`, `src/it/` are unambiguous
          # JVM build-tool conventions).
          next if JavaEngine.test_path?(path)
          webflux_base_path = find_base_path(path, webflux_base_path_map)
          project_root = project_root_for(path)
          path_config = path_configs[project_root]? || SpringPathConfig.new
          stomp_application_prefixes = stomp_prefixes[project_root]? || [""]
          configured_base_path = path_config.web_base_path
          configured_base_path = webflux_base_path if configured_base_path.empty?
          content = read_file_content(path)

          # Only files that mention Spring MVC / Feign bindings carry
          # annotation-based routes. Reactive `router().route()` files
          # land in the `else` branch below.
          spring_web_bind_package = "org.springframework.web.bind.annotation."
          feign_client_package = "org.springframework.cloud.openfeign.FeignClient"
          http_exchange_package = "org.springframework.web.service.annotation."
          has_spring_bindings = content.includes?(spring_web_bind_package)
          has_feign_bindings = content.includes?(feign_client_package) || content.includes?("@FeignClient")
          has_http_exchange_bindings = http_exchange_bindings?(content, http_exchange_package)
          has_gateway_bindings = content.includes?("RouteLocatorBuilder") ||
                                 content.includes?("PredicateSpec") ||
                                 content.includes?("org.springframework.cloud.gateway")
          has_websocket_bindings = content.includes?("org.springframework.web.socket.config.annotation") ||
                                   content.includes?("WebSocketMessageBrokerConfigurer") ||
                                   content.includes?("@EnableWebSocketMessageBroker")
          has_message_mapping_bindings = content.includes?("org.springframework.messaging.handler.annotation") ||
                                         content.includes?("@MessageMapping") ||
                                         content.includes?("@SubscribeMapping")
          has_resource_handler_bindings = content.includes?("ResourceHandlerRegistry") ||
                                          content.includes?("addResourceHandler")

          if has_spring_bindings || has_feign_bindings || has_http_exchange_bindings || has_gateway_bindings ||
             has_websocket_bindings || has_message_mapping_bindings || has_resource_handler_bindings
            # Single tree-sitter parse for the whole file — every
            # extraction below pulls from the same root so a
            # controller with N routes pays for 1 parse instead of
            # the previous 4 + 2N. The DTO index, FeignClient
            # detection, route discovery, consumes lookup, and
            # parameter walks all consume `root`.
            Noir::TreeSitter.parse_java(content) do |root|
              # Skip files without a package declaration — legacy filter
              # that avoids scanning test stubs / throwaway snippets.
              package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
              next if package_name.empty?

              dto_index = dto_builder.build_for_with_root(path, content, root)
              feign_clients = Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes_from(root, content)
              http_exchange_clients = Noir::TreeSitterJavaParameterExtractor.extract_http_exchange_client_classes_from(root, content)
              visible_meta_mappings = visible_meta_annotation_mappings(path, content, package_name, meta_annotation_index)
              imports = java_imports(content)

              Noir::TreeSitterJavaRouteExtractor.extract_routes_from(root, content, visible_meta_mappings).each do |route|
                is_feign_client = feign_clients.includes?(route.class_name)
                is_http_exchange_client = http_exchange_clients.includes?(route.class_name)
                is_internal_client = is_feign_client || is_http_exchange_client

                parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes_from(
                  root, content, route.class_name, route.method_name
                )
                # The POST form-binding default is applied per-parameter in
                # the extractor so an explicit `@RequestBody` resolves to
                # "json" rather than inheriting "form".

                parameters = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters_from(
                  root, content, route.class_name, route.method_name, route.verb, parameter_format, dto_index, route.line
                )
                merge_route_condition_params(parameters, route.params)

                # Drop the trailing `/` on webflux_base_path when the
                # route path already starts with one, so the join
                # doesn't produce `//`.
                base_path = is_internal_client ? "" : configured_base_path
                if base_path.ends_with?("/") && route.path.starts_with?("/")
                  base_path = base_path[..-2]
                end

                line = route.line + 1
                details = Details.new(PathInfo.new(path, line))

                endpoint = Endpoint.new(
                  join_paths(base_path, route.path), route.verb, parameters, details, is_internal_client
                )

                # 1-hop callees out of the handler method body. Cross-file
                # definition resolution is intentionally out of scope —
                # `Callee#path` points at the call site, matching every
                # other analyzer's first-cut honest scope.
                if include_callee && !(route.class_name.empty? || route.method_name.empty?)
                  Noir::JavaCalleeExtractor.callees_in_method(
                    root, content, path, route.class_name, route.method_name, route.line
                  ).each do |entry|
                    name, callee_path, callee_line = entry
                    endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end

                @result << endpoint
              end

              Noir::TreeSitterJavaRouteExtractor.extract_controller_interface_implementations_from(root, content, visible_meta_mappings).each do |implementation|
                implementation.interface_names.each do |interface_name|
                  visible_interface_routes(interface_route_index, path, package_name, imports, interface_name).each do |entry|
                    entry_route = entry.route
                    implementation.paths.each do |implementation_path|
                      inherited_path = join_paths(implementation_path, entry_route.path)
                      parameter_format = nil
                      parameters = [] of Param

                      Noir::TreeSitter.parse_java(entry.source) do |interface_root|
                        interface_dto_index = dto_builder.build_for_with_root(entry.path, entry.source, interface_root)
                        parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes_from(
                          interface_root, entry.source, entry_route.class_name, entry_route.method_name
                        )
                        # POST form-binding default applied per-parameter in
                        # the extractor (keeps `@RequestBody` as "json").

                        parameters = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters_from(
                          interface_root, entry.source, entry_route.class_name, entry_route.method_name,
                          entry_route.verb, parameter_format, interface_dto_index, entry_route.line
                        )
                        merge_route_condition_params(parameters, implementation.params + entry_route.params)
                      end

                      details = Details.new(PathInfo.new(entry.path, entry_route.line + 1))
                      endpoint = Endpoint.new(
                        join_paths(configured_base_path, inherited_path), entry_route.verb, parameters, details
                      )

                      # The route is declared on the interface (springdoc /
                      # OpenAPI `*Api` contracts), but the behaviour — and
                      # thus the callees worth surfacing for ai-context —
                      # lives in the `@Override` method on the concrete
                      # controller currently being walked. Pull 1-hop
                      # callees from that implementing body rather than the
                      # empty interface method.
                      if include_callee && !(implementation.class_name.empty? || entry_route.method_name.empty?)
                        Noir::JavaCalleeExtractor.callees_in_method(
                          root, content, path, implementation.class_name, entry_route.method_name
                        ).each do |callee_entry|
                          name, callee_path, callee_line = callee_entry
                          endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                        end
                      end

                      @result << endpoint
                    end
                  end
                end
              end

              if has_websocket_bindings
                constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
                collect_stomp_endpoints(content, constants).each do |entry|
                  endpoint_path, line = entry
                  endpoint = Endpoint.new(join_paths(configured_base_path, endpoint_path), "GET", Details.new(PathInfo.new(path, line)))
                  endpoint.protocol = "ws"
                  @result << endpoint
                end
              end

              if has_message_mapping_bindings
                constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
                collect_message_mapping_endpoints(root, content, constants, stomp_application_prefixes).each do |entry|
                  verb, destination, line = entry
                  endpoint = Endpoint.new(destination, verb, Details.new(PathInfo.new(path, line)))
                  endpoint.protocol = "ws"
                  @result << endpoint
                end
              end

              if has_resource_handler_bindings
                constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
                collect_resource_handler_endpoints(content, constants).each do |entry|
                  endpoint_path, line = entry
                  @result << Endpoint.new(join_paths(configured_base_path, endpoint_path), "GET", Details.new(PathInfo.new(path, line)))
                end
              end
            end
          else
            # Reactive routes declared via `router().route(...).andRoute(...)`
            # — regex-scoped because the builder-pattern shape isn't
            # worth a dedicated tree-sitter walk yet.
            route_blocks = [] of Tuple(Array(Tuple(Int32, String, String, String)), Array(Tuple(Int32, Int32, String)))
            reactive_callees = {} of String => Array(Callee)

            # Single tree-sitter parse for the whole reactive file: the
            # constant table and the `this::handler` callee resolution both
            # read from this one `root`, so the file isn't parsed twice
            # when callees are requested (and constants are resolved once,
            # not once-per-block).
            Noir::TreeSitter.parse_java(content) do |root|
              constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
              content.scan(REGEX_ROUTER_CODE_BLOCK) do |route_code|
                method_code = route_code[0]
                # Pick up `nest(RequestPredicates.path("/prefix"), ...)`
                # / `nest(path("/prefix"), ...)` byte ranges so verb
                # calls inside the nested lambda get the prefix added.
                # Servlet-fn and WebFlux both use this idiom heavily;
                # without prefix awareness routes like
                # `route().nest(path("/product"), builder ->
                # builder.GET("/name/{name}", ...))` surfaced as
                # `GET /name/{name}` instead of `GET /product/name/{name}`.
                route_blocks << {collect_router_route_calls(method_code, constants), collect_nest_prefixes(method_code, constants)}
              end

              # Resolve same-file `this::handler` method bodies to 1-hop
              # callees so reactive endpoints carry handler context too.
              if include_callee
                wanted = Set(String).new
                route_blocks.each { |calls, _| calls.each { |call| wanted << call[3] unless call[3].empty? } }
                reactive_callees = build_reactive_method_callees(root, content, path, wanted)
              end
            end

            route_blocks.each do |calls, nest_prefixes|
              calls.each do |call|
                pos, method, endpoint, handler_ref = call
                nest_prefix = ""
                nest_prefixes.each do |start_b, end_b, prefix|
                  if pos >= start_b && pos < end_b
                    nest_prefix = join_paths(nest_prefix, prefix)
                  end
                end
                composed = nest_prefix.empty? ? endpoint : join_paths(nest_prefix, endpoint)
                details = Details.new(PathInfo.new(path))
                reactive_endpoint = Endpoint.new(join_paths(configured_base_path, composed), method, details)

                if include_callee && !handler_ref.empty?
                  if handler_callees = reactive_callees[handler_ref]?
                    handler_callees.each { |callee| reactive_endpoint.push_callee(callee) }
                  end
                end

                @result << reactive_endpoint
              end
            end
          end
        end
      end
      Fiber.yield

      @result
    end

    private def collect_meta_annotation_index(file_list : Array(String)) : SpringMetaAnnotationIndex
      index = SpringMetaAnnotationIndex.new
      spring_web_bind_package = "org.springframework.web.bind.annotation."

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".java")
        next if JavaEngine.test_path?(path)

        content = read_file_content(path)
        next unless content.includes?(spring_web_bind_package)
        # Composed (meta) mapping annotations are declared as Java
        # annotation types (`@interface`). A file without one cannot
        # contribute to this index, so skip the tree-sitter parse for
        # the (overwhelming) majority of regular controller classes.
        next unless content.includes?("@interface")

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
          Noir::TreeSitterJavaRouteExtractor.extract_meta_mappings_from(root, content, constants).each do |name, mapping|
            index.add(project_root_for(path), package_name, name, mapping)
          end
        end
      end

      index
    end

    private def collect_interface_route_index(file_list : Array(String),
                                              meta_annotation_index : SpringMetaAnnotationIndex) : SpringInterfaceRouteIndex
      index = SpringInterfaceRouteIndex.new
      spring_web_bind_package = "org.springframework.web.bind.annotation."
      http_exchange_package = "org.springframework.web.service.annotation."

      file_list.each do |path|
        next unless File.exists?(path) && path.ends_with?(".java")
        next if JavaEngine.test_path?(path)

        content = read_file_content(path)
        # Inheritable routes come from Java interfaces (Feign, Spring HTTP
        # Interface, OpenAPI-style `*Api`) and from `abstract` base
        # classes that concrete controllers extend. Files with neither
        # keyword — the bulk of controller classes — can't contribute, so
        # skip the parse before the annotation gate below.
        next unless content.includes?("interface") || content.includes?("abstract")
        next unless content.includes?(spring_web_bind_package) || http_exchange_bindings?(content, http_exchange_package) ||
                    content.includes?("@RequestMapping") ||
                    content.includes?("@GetMapping") || content.includes?("@PostMapping")

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          visible_meta_mappings = visible_meta_annotation_mappings(path, content, package_name, meta_annotation_index)
          Noir::TreeSitterJavaRouteExtractor.extract_interface_routes_from(root, content, visible_meta_mappings).each do |interface_name, routes|
            routes.each do |route|
              index.add(project_root_for(path), package_name, interface_name, SpringInterfaceRouteEntry.new(route, path, content, package_name))
            end
          end
        end
      end

      index
    end

    private def http_exchange_bindings?(content : String, package_name : String) : Bool
      content.includes?(package_name) ||
        content.includes?("@HttpExchange") ||
        content.includes?("@GetExchange") ||
        content.includes?("@PostExchange") ||
        content.includes?("@PutExchange") ||
        content.includes?("@PatchExchange") ||
        content.includes?("@DeleteExchange")
    end

    private def visible_meta_annotation_mappings(path : String,
                                                 content : String,
                                                 package_name : String,
                                                 index : SpringMetaAnnotationIndex) : Hash(String, SpringRouteMapping)
      mappings = Hash(String, SpringRouteMapping).new
      project_root = project_root_for(path)
      merge_meta_package(mappings, index.by_package[{project_root, package_name}]?)

      java_imports(content).each do |import_name|
        if import_name.ends_with?(".*")
          merge_meta_package(mappings, index.by_package[{project_root, import_name[...-2]}]?)
        elsif mapping = index.by_fqcn[{project_root, import_name}]?
          mappings[import_name.split('.').last] = mapping
        end
      end

      mappings
    end

    private def visible_interface_routes(index : SpringInterfaceRouteIndex,
                                         path : String,
                                         package_name : String,
                                         imports : Array(String),
                                         interface_name : String) : Array(SpringInterfaceRouteEntry)
      routes = [] of SpringInterfaceRouteEntry
      seen = Set(String).new
      project_root = project_root_for(path)

      add_interface_routes(routes, seen, index.by_package[{project_root, package_name}]?.try(&.[interface_name]?))

      imports.each do |import_name|
        if import_name.ends_with?(".*")
          add_interface_routes(routes, seen, index.by_package[{project_root, import_name[...-2]}]?.try(&.[interface_name]?))
        elsif import_name.ends_with?(".#{interface_name}")
          add_interface_routes(routes, seen, index.by_fqcn[{project_root, import_name}]?)
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

    private def merge_route_condition_params(parameters : Array(Param), condition_params : Array(Param))
      condition_params.each do |param|
        next if parameters.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
        parameters << param
      end
    end

    private def merge_meta_package(target : Hash(String, SpringRouteMapping),
                                   package_mappings : Hash(String, SpringRouteMapping)?)
      return unless package_mappings

      package_mappings.each do |name, mapping|
        target[name] ||= mapping
      end
    end

    private def java_imports(content : String) : Array(String)
      imports = [] of String
      content.scan(/^\s*import\s+(?!static\s)([A-Za-z_][A-Za-z0-9_.]*(?:\.\*)?)\s*;/m) do |match|
        imports << match[1]
      end
      imports
    end

    private def collect_stomp_endpoints(content : String,
                                        constants : Hash(String, String)) : Array(Tuple(String, Int32))
      endpoints = [] of Tuple(String, Int32)
      offset = 0

      while marker = content.index("addEndpoint", offset)
        offset = marker + 11
        next unless add_endpoint_call_name?(content, marker)

        open_idx = content.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        args = content[(open_idx + 1)...close_idx]
        line = content[0...marker].count('\n') + 1
        top_level_arguments(args).each do |arg|
          if endpoint_path = resolve_router_path(arg, constants)
            endpoints << {endpoint_path, line}
          end
        end
      end

      endpoints
    end

    private def collect_resource_handler_endpoints(content : String,
                                                   constants : Hash(String, String)) : Array(Tuple(String, Int32))
      endpoints = [] of Tuple(String, Int32)
      offset = 0

      while marker = content.index("addResourceHandler", offset)
        offset = marker + 18
        next unless method_call_name?(content, marker, 18)

        open_idx = content.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        args = content[(open_idx + 1)...close_idx]
        line = content[0...marker].count('\n') + 1
        top_level_arguments(args).each do |arg|
          if endpoint_path = resolve_router_path(arg, constants)
            endpoints << {endpoint_path, line}
          end
        end
      end

      endpoints.uniq
    end

    private def collect_message_mapping_endpoints(root : LibTreeSitter::TSNode,
                                                  content : String,
                                                  constants : Hash(String, String),
                                                  application_prefixes : Array(String)) : Array(Tuple(String, String, Int32))
      endpoints = [] of Tuple(String, String, Int32)
      walk_message_mapping_classes(root, content, constants, application_prefixes, [""], endpoints)
      endpoints
    end

    private def walk_message_mapping_classes(node : LibTreeSitter::TSNode,
                                             content : String,
                                             constants : Hash(String, String),
                                             application_prefixes : Array(String),
                                             outer_prefixes : Array(String),
                                             endpoints : Array(Tuple(String, String, Int32)),
                                             depth = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "class_declaration"
        class_paths = message_mapping_paths(node, content, constants)
        class_paths = [""] if class_paths.empty?
        prefixes = [] of String
        outer_prefixes.each do |outer_prefix|
          class_paths.each do |class_path|
            prefixes << join_paths(outer_prefix, class_path)
          end
        end

        if body = Noir::TreeSitter.field(node, "body")
          Noir::TreeSitter.each_named_child(body) do |member|
            case Noir::TreeSitter.node_type(member)
            when "method_declaration"
              collect_message_mapping_method_endpoints(member, content, constants, application_prefixes, prefixes, endpoints)
            when "class_declaration"
              walk_message_mapping_classes(member, content, constants, application_prefixes, prefixes, endpoints, depth + 1)
            end
          end
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_message_mapping_classes(child, content, constants, application_prefixes, outer_prefixes, endpoints, depth + 1)
      end
    end

    private def collect_message_mapping_method_endpoints(method : LibTreeSitter::TSNode,
                                                         content : String,
                                                         constants : Hash(String, String),
                                                         application_prefixes : Array(String),
                                                         class_prefixes : Array(String),
                                                         endpoints : Array(Tuple(String, String, Int32)))
      each_java_annotation(method, content) do |name, args_node, line|
        verb =
          case name
          when "MessageMapping"   then "SEND"
          when "SubscribeMapping" then "SUBSCRIBE"
          end
        next unless verb

        paths = annotation_string_values(args_node, content, constants)
        next if paths.empty?

        application_prefixes.each do |application_prefix|
          class_prefixes.each do |class_prefix|
            paths.each do |path|
              endpoints << {verb, join_paths(application_prefix, join_paths(class_prefix, path)), line + 1}
            end
          end
        end
      end
    end

    private def message_mapping_paths(decl : LibTreeSitter::TSNode,
                                      content : String,
                                      constants : Hash(String, String)) : Array(String)
      paths = [] of String
      each_java_annotation(decl, content) do |name, args_node|
        next unless name == "MessageMapping"
        paths.concat(annotation_string_values(args_node, content, constants))
      end
      paths
    end

    private def add_endpoint_call_name?(code : String, marker : Int32) : Bool
      method_call_name?(code, marker, 11)
    end

    private def method_call_name?(code : String, marker : Int32, name_size : Int32) : Bool
      before = marker.zero? ? '\0' : code[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = marker + name_size
      while after_idx < code.size && code[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < code.size && code[after_idx] == '('
    end

    private def each_java_annotation(decl : LibTreeSitter::TSNode,
                                     content : String,
                                     &)
      mods = java_modifiers(decl)
      return unless mods

      Noir::TreeSitter.each_named_child(mods) do |ann|
        type = Noir::TreeSitter.node_type(ann)
        next unless type == "annotation" || type == "marker_annotation"

        name_node = Noir::TreeSitter.field(ann, "name")
        next unless name_node

        name = simple_java_annotation_name(Noir::TreeSitter.node_text(name_node, content))
        args = Noir::TreeSitter.field(ann, "arguments")
        yield name, args, Noir::TreeSitter.node_start_row(ann)
      end
    end

    private def java_modifiers(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "modifiers"
      end
      nil
    end

    private def simple_java_annotation_name(name : String) : String
      if index = name.rindex('.')
        name[(index + 1)..]
      else
        name
      end
    end

    private def annotation_string_values(args_node : LibTreeSitter::TSNode?,
                                         content : String,
                                         constants : Hash(String, String)) : Array(String)
      return [] of String unless args_node

      text = Noir::TreeSitter.node_text(args_node, content).strip
      return [] of String unless text.starts_with?('(') && text.ends_with?(')')

      values = [] of String
      top_level_arguments(text[1...-1]).each do |arg|
        collect_annotation_argument_values(arg, constants, values)
      end
      values
    end

    private def collect_annotation_argument_values(argument : String,
                                                   constants : Hash(String, String),
                                                   values : Array(String))
      arg = argument.strip
      return if arg.empty?

      if equals = top_level_equals(arg)
        key = arg[...equals].strip
        return unless key == "value" || key == "path"
        arg = arg[(equals + 1)..].strip
      end

      if arg.starts_with?('{') && arg.ends_with?('}')
        top_level_arguments(arg[1...-1]).each do |entry|
          if value = resolve_router_path(entry, constants)
            values << value
          end
        end
      elsif value = resolve_router_path(arg, constants)
        values << value
      end
    end

    private def top_level_equals(expression : String) : Int32?
      depth = 0
      in_string = false
      escape = false

      expression.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '='
          return index if depth.zero?
        end
      end

      nil
    end

    # Collect every `nest(<predicate-with-path>, ...)` block in the
    # router code along with the path prefix it carries and the
    # byte range of its parenthesised argument list. Returns
    # `[{start_byte, end_byte, prefix}, ...]`. Inner verb calls
    # whose match position falls inside `[start, end)` should have
    # `prefix` prepended.
    private def collect_router_route_calls(code : String,
                                           constants : Hash(String, String)) : Array(Tuple(Int32, String, String, String))
      calls = [] of Tuple(Int32, String, String, String)

      code.scan(REGEX_ROUTE_CALL) do |match|
        open_idx = (match.end || 0) - 1
        next if open_idx < 0
        close_idx = find_matching_paren(code, open_idx)
        next unless close_idx

        args = code[(open_idx + 1)...close_idx]
        arg_list = top_level_arguments(args)
        path = resolve_router_path(arg_list.first? || "", constants)
        next unless path

        # The handler is the second argument of `.GET("/x", this::handle)`
        # / `route(RequestPredicates.GET("/x"), this::handle)`. Capture a
        # same-file method-reference name so the reactive branch can pull
        # 1-hop callees out of that handler body (WebFlux/servlet-fn
        # RouterFunction handlers carry the real behaviour worth surfacing
        # for ai-context).
        handler_ref = arg_list.size >= 2 ? handler_method_reference(arg_list[1]) : ""
        calls << {match.begin || 0, match[2], path.gsub(/\n/, ""), handler_ref}
      end

      calls
    end

    # Extract the method name from a functional-handler argument when it
    # is a same-file method reference (`this::handle`, `Type::handle`,
    # `handler::handle`). Returns "" for lambdas and anything else — those
    # carry no resolvable same-file declaration to walk.
    private def handler_method_reference(arg : String) : String
      expr = arg.strip
      if idx = expr.rindex("::")
        name = expr[(idx + 2)..].strip
        return name if name.matches?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
      end
      ""
    end

    # Walk the already-parsed `root` and return `{handler_method_name =>
    # [Callee]}` for every wanted handler, mirroring the Vert.x analyzer's
    # method-reference callee resolution. Shares the caller's parse so a
    # reactive file is read once. Name collisions keep the first
    # declaration (reactive router configs rarely repeat handler names in
    # one file).
    private def build_reactive_method_callees(root : LibTreeSitter::TSNode,
                                              content : String,
                                              path : String,
                                              wanted : Set(String)) : Hash(String, Array(Callee))
      result = {} of String => Array(Callee)
      return result if wanted.empty?

      walk_reactive_method_declarations(root) do |method|
        name_node = Noir::TreeSitter.field(method, "name")
        next unless name_node
        method_name = Noir::TreeSitter.node_text(name_node, content)
        next unless wanted.includes?(method_name)
        next if result.has_key?(method_name)

        body = Noir::TreeSitter.field(method, "body")
        next unless body
        result[method_name] = Noir::JavaCalleeExtractor.callees_in_body(body, content, path).map do |(name, callee_path, callee_line)|
          Callee.new(name, path: callee_path, line: callee_line)
        end
      end

      result
    end

    private def walk_reactive_method_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_reactive_method_declarations(child, &block)
      end
    end

    private def collect_nest_prefixes(code : String,
                                      constants : Hash(String, String)) : Array(Tuple(Int32, Int32, String))
      regions = [] of Tuple(Int32, Int32, String)

      offset = 0
      while nest_marker = code.index("nest", offset)
        offset = nest_marker + 4
        next unless nest_call_name?(code, nest_marker)

        open_idx = code.index('(', nest_marker)
        next unless open_idx
        close_idx = find_matching_paren(code, open_idx)
        next unless close_idx

        args = code[(open_idx + 1)...close_idx]
        predicate = first_argument(args)
        next unless prefix = path_predicate_prefix(predicate, constants)

        regions << {open_idx, close_idx, prefix}
      end

      regions
    end

    private def nest_call_name?(code : String, nest_marker : Int32) : Bool
      before = nest_marker.zero? ? '\0' : code[nest_marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = nest_marker + 4
      while after_idx < code.size && code[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < code.size && code[after_idx] == '('
    end

    private def first_argument(args : String) : String
      depth = 0
      in_string = false
      escape = false

      args.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          return args[...index] if depth.zero?
        end
      end

      args
    end

    private def top_level_arguments(args : String) : Array(String)
      values = [] of String
      start = 0
      depth = 0
      in_string = false
      escape = false

      args.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          if depth.zero?
            values << args[start...index]
            start = index + 1
          end
        end
      end

      values << args[start..]
      values.map(&.strip).reject(&.empty?)
    end

    private def path_predicate_prefix(predicate : String,
                                      constants : Hash(String, String)) : String?
      offset = 0
      while path_marker = predicate.index("path", offset)
        offset = path_marker + 4
        next unless path_call_name?(predicate, path_marker)

        open_idx = predicate.index('(', path_marker)
        next unless open_idx
        close_idx = find_matching_paren(predicate, open_idx)
        next unless close_idx

        args = predicate[(open_idx + 1)...close_idx]
        path_arg = first_argument(args)
        if path = resolve_router_path(path_arg, constants)
          return path
        end
      end

      nil
    end

    private def path_call_name?(code : String, path_marker : Int32) : Bool
      before = path_marker.zero? ? '\0' : code[path_marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = path_marker + 4
      while after_idx < code.size && code[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < code.size && code[after_idx] == '('
    end

    private def resolve_router_path(expression : String,
                                    constants : Hash(String, String),
                                    depth = 0) : String?
      return if depth > 16

      expr = strip_wrapping_parentheses(expression.strip)
      return if expr.empty?

      if expr.starts_with?('"') && expr.ends_with?('"')
        return decode_router_string(expr)
      end

      if expr.includes?("+")
        parts = split_top_level_concat(expr)
        return if parts.empty?
        values = parts.compact_map { |part| resolve_router_path(part, constants, depth + 1) }
        return unless values.size == parts.size
        return values.join
      end

      resolve_router_constant(expr, constants)
    end

    private def resolve_router_constant(name : String,
                                        constants : Hash(String, String)) : String?
      cleaned = name.strip
      if value = constants[cleaned]?
        return value
      end

      if index = cleaned.rindex('.')
        short_name = cleaned[(index + 1)..]
        return constants[short_name]? if constants[short_name]?
      end

      nil
    end

    private def split_top_level_concat(expression : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escape = false

      expression.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '+'
          if depth.zero?
            parts << expression[start...index]
            start = index + 1
          end
        end
      end

      parts << expression[start..]
      parts.map(&.strip).reject(&.empty?)
    end

    private def strip_wrapping_parentheses(expression : String) : String
      result = expression
      while result.starts_with?('(') && result.ends_with?(')')
        close_idx = find_matching_paren(result, 0)
        break unless close_idx == result.size - 1
        result = result[1...-1].strip
      end
      result
    end

    private def decode_router_string(raw : String) : String
      return raw unless raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"')
      raw[1...-1].gsub(/\\(["\\])/, "\\1")
    end

    # Find the matching `)` for the `(` at `open_idx`, skipping
    # string literals so `"(foo)"` doesn't perturb depth.
    private def find_matching_paren(code : String, open_idx : Int32) : Int32?
      # Scan by CHARACTER (not byte): open_idx comes from char-based String#index
      # / MatchData and callers char-slice with the returned index. A byte scan
      # corrupts both on multi-byte UTF-8 (i18n comments/literals). ASCII-identical.
      depth = 1
      in_string = false
      escape = false
      code.each_char_with_index do |c, i|
        next if i <= open_idx
        if in_string
          if escape
            escape = false
          elsif c == '\\'
            escape = true
          elsif c == '"'
            in_string = false
          end
        else
          case c
          when '"' then in_string = true
          when '(' then depth += 1
          when ')' then depth -= 1
          end
        end
        return i if depth.zero?
      end
      nil
    end

    private def path_configs_for(file_list : Array(String)) : Hash(String, SpringPathConfig)
      configs = Hash(String, SpringPathConfig).new
      project_roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".java")
        project_roots << project_root_for(path)
      end

      project_roots.each do |root|
        configs[root] = path_config_for(root)
      end

      configs
    end

    private def stomp_application_prefixes_for(file_list : Array(String)) : Hash(String, Array(String))
      prefixes = Hash(String, Array(String)).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".java")

        content = read_file_content(path)
        next unless content.includes?("setApplicationDestinationPrefixes")

        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content)
        collected = collect_stomp_application_prefixes(content, constants)
        next if collected.empty?

        root = project_root_for(path)
        prefixes[root] ||= [] of String
        prefixes[root].concat(collected)
        prefixes[root] = prefixes[root].uniq
      end

      prefixes
    end

    private def collect_stomp_application_prefixes(content : String,
                                                   constants : Hash(String, String)) : Array(String)
      prefixes = [] of String
      offset = 0

      while marker = content.index("setApplicationDestinationPrefixes", offset)
        offset = marker + 33
        next unless method_call_name?(content, marker, 33)

        open_idx = content.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        args = content[(open_idx + 1)...close_idx]
        top_level_arguments(args).each do |arg|
          if arg.starts_with?('{') && arg.ends_with?('}')
            top_level_arguments(arg[1...-1]).each do |entry|
              if prefix = resolve_router_path(entry, constants)
                prefixes << prefix
              end
            end
          elsif prefix = resolve_router_path(arg, constants)
            prefixes << prefix
          end
        end
      end

      prefixes
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
      if value = yaml_string_value(path, "server", "servlet", "context-path")
        values["server.servlet.context-path"] = value
      end
      if value = yaml_string_value(path, "spring", "webflux", "base-path")
        values["spring.webflux.base-path"] = value
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

    def find_base_path(current_path : String, base_paths : Hash(String, String))
      base_paths.keys.sort_by!(&.size).reverse!.each do |path|
        if current_path.starts_with?(path)
          return base_paths[path]
        end
      end

      ""
    end
  end
end
