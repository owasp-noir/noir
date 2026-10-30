require "../../../models/analyzer"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../miniparsers/java_parameter_extractor_ts"
require "../../../miniparsers/java_callee_extractor"
require "../../../utils/spring_property_path"
require "../../engines/java_engine"
require "../../../utils/path_scope"
require "../../../utils/url_path"
require "../../../utils/top_level_split"
require "yaml"

module Analyzer::Java
  class Spring < Analyzer
    analyzer_for "java_spring"

    include JavaEngine

    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    # Where a router statement starts: `route(` / `route()` and the
    # `RouterFunctions.nest(path(...), route()...)` form, whose prefix sits
    # before the `route(`.
    ROUTER_BLOCK_START_RE = /(?<![\w$])(?:route|nest)\s*\(/
    REGEX_ROUTE_CALL      = /((?:andRoute|route)\s*\(|\.)\s*(?:RequestPredicates\.)?(GET|POST|DELETE|PUT|PATCH|HEAD|OPTIONS)\s*\(/

    SPRING_WEB_BIND_PACKAGE      = "org.springframework.web.bind.annotation."
    FEIGN_CLIENT_PACKAGE         = "org.springframework.cloud.openfeign.FeignClient"
    SPRING_HTTP_EXCHANGE_PACKAGE = "org.springframework.web.service.annotation."

    # Every `content.includes?(...)` below used to be its own Rabin-Karp
    # pass over the whole file. This analyzer asks ~30 such questions per
    # `.java` file across three walks, and on a monorepo the overwhelming
    # majority of files answer "no" to all of them. One precompiled
    # `Regex.union` (PCRE2 JIT, via `content_matches?`) is the same
    # predicate in a single pass — see the note on `Analyzer#content_matches?`.
    WEBSOCKET_BINDING_RE = Regex.union(
      "org.springframework.web.socket.config.annotation",
      "WebSocketMessageBrokerConfigurer",
      "@EnableWebSocketMessageBroker",
    )
    MESSAGE_MAPPING_BINDING_RE = Regex.union(
      "org.springframework.messaging.handler.annotation",
      "@MessageMapping",
      "@SubscribeMapping",
    )
    RESOURCE_HANDLER_BINDING_RE = Regex.union("ResourceHandlerRegistry", "addResourceHandler")

    # The OR of every marker the annotation branch keys off. A file that
    # misses this cannot set any of the individual flags, so the per-flag
    # scans only run for the handful of files that get past it.
    ANY_BINDING_RE = Regex.union(
      SPRING_WEB_BIND_PACKAGE,
      FEIGN_CLIENT_PACKAGE, "@FeignClient",
      SPRING_HTTP_EXCHANGE_PACKAGE,
      "@HttpExchange", "@GetExchange", "@PostExchange",
      "@PutExchange", "@PatchExchange", "@DeleteExchange",
      "RouteLocatorBuilder", "PredicateSpec", "org.springframework.cloud.gateway",
      "org.springframework.web.socket.config.annotation",
      "WebSocketMessageBrokerConfigurer", "@EnableWebSocketMessageBroker",
      "org.springframework.messaging.handler.annotation",
      "@MessageMapping", "@SubscribeMapping",
      "ResourceHandlerRegistry", "addResourceHandler",
    )

    # `build_spring_indexes` gate: neither index can want a file that
    # mentions neither marker.
    STOMP_PREFIX_RE           = Regex.union("setApplicationDestinationPrefixes")
    SPRING_WEB_BIND_RE        = Regex.union(SPRING_WEB_BIND_PACKAGE)
    META_ANNOTATION_RE        = Regex.union("@interface")
    SPRING_INDEX_PRESCREEN_RE = Regex.union("setApplicationDestinationPrefixes", SPRING_WEB_BIND_PACKAGE)
    INJECTED_META_RE          = Regex.union(Noir::TreeSitterJavaParameterExtractor::INJECTED_PARAM_ANNOTATIONS.map { |name| "@#{name}" })
    # `implements Formatter<PetType>` / `Converter<String, PetType>`: the target type.
    CONVERTER_TARGET_RE = /\b(?:Formatter|Converter)\s*<\s*(?:[\w.]+\s*,\s*)?(?:[\w]+\.)*(\w+)\s*>/
    # `dataBinder.setDisallowedFields("id", "*.id")` in an `@InitBinder`.
    DISALLOWED_FIELDS_RE = /\bsetDisallowedFields\s*\(([^)]*)\)/

    # `collect_interface_route_index` gates.
    INTERFACE_OR_ABSTRACT_RE  = Regex.union("interface", "abstract")
    INTERFACE_ROUTE_MARKER_RE = Regex.union(
      SPRING_WEB_BIND_PACKAGE,
      SPRING_HTTP_EXCHANGE_PACKAGE,
      "@HttpExchange", "@GetExchange", "@PostExchange",
      "@PutExchange", "@PatchExchange", "@DeleteExchange",
      "@RequestMapping", "@GetMapping", "@PostMapping",
    )

    alias SpringRouteMapping = Noir::TreeSitterJavaRouteExtractor::ClassMapping
    alias SpringRoute = Noir::TreeSitterJavaRouteExtractor::Route
    alias PackageScopeKey = Tuple(String, String)

    private struct SpringMetaAnnotationIndex
      getter by_package : Hash(PackageScopeKey, Hash(String, SpringRouteMapping))
      getter by_fqcn : Hash(PackageScopeKey, SpringRouteMapping)

      def initialize
        @by_package = Hash(PackageScopeKey, Hash(String, SpringRouteMapping)).new
        @by_fqcn = Hash(PackageScopeKey, SpringRouteMapping).new
      end

      # Each mapping is filed under its module (`project_root`) and under the
      # configured scan base (`scope_base`), so a controller can use a
      # meta-annotation declared in a sibling Maven/Gradle module. The
      # module's own declaration wins (see `visible_meta_annotation_mappings`).
      def add(project_root : String, scope_base : String, package_name : String, annotation_name : String, mapping : SpringRouteMapping)
        {project_root, "base:#{scope_base}"}.each do |scope|
          package_mappings = @by_package[{scope, package_name}] ||= Hash(String, SpringRouteMapping).new
          package_mappings[annotation_name] ||= mapping

          unless package_name.empty?
            @by_fqcn[{scope, "#{package_name}.#{annotation_name}"}] ||= mapping
          end
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
      include_callee = callees_needed?
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      # `.java` from the extension index, tests dropped once. Previous
      # shape walked the whole monorepo `file_map` four times (path
      # configs, STOMP prefixes, meta annotations, interface routes)
      # before the main route pass — each pass re-reading and often
      # re-parsing the same files. Indexes are now built in at most two
      # content walks over the Java source set only; webflux /
      # servlet context paths come from `path_config_for` (application.yml
      # / .properties under each project root).
      java_files = get_files_by_extension(".java").reject { |path| JavaEngine.test_path?(base_relative_path(path)) }
      path_configs, spring_property_maps, stomp_prefixes, meta_annotation_index, interface_route_index, injected_annotation_index, converted_type_index, advice_disallowed_index =
        build_spring_indexes(java_files)

      java_files.each do |path|
        project_root = project_root_for(path)
        path_config = path_configs[project_root]? || SpringPathConfig.new
        spring_properties = spring_property_maps[project_root]? || {} of String => String
        stomp_application_prefixes = stomp_prefixes[project_root]? || [""]
        configured_base_path = path_config.web_base_path
        injected_annotations = injected_annotation_index[project_root]?
        resolver_bound = resolver_injected_annotations(path)
        injected_annotations = (injected_annotations || Set(String).new) | resolver_bound unless resolver_bound.empty?
        converted_types = converted_type_index[project_root]?
        content = read_file_content(path)
        # ponytail: file-scoped, ignores `@InitBinder("name")` targets and advice selectors.
        disallowed_fields = disallowed_binder_fields(content) + (advice_disallowed_index[project_root]? || [] of String)
        @result.concat(spring_security_endpoints(path, configured_base_path))

        # Only files that mention Spring MVC / Feign bindings carry
        # annotation-based routes. Reactive `router().route()` files
        # land in the `else` branch below. `ANY_BINDING_RE` is the OR of
        # every marker the branch below keys off, so one pass decides
        # whether the per-flag scans are worth running at all.
        if content_matches?(content, ANY_BINDING_RE)
          has_websocket_bindings = content_matches?(content, WEBSOCKET_BINDING_RE)
          has_message_mapping_bindings = content_matches?(content, MESSAGE_MAPPING_BINDING_RE)
          has_resource_handler_bindings = content_matches?(content, RESOURCE_HANDLER_BINDING_RE)

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

            dto_index = with_default_json_naming(dto_builder.build_for_with_root(path, content, root), path)
            feign_clients = Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes_from(root, content)
            http_exchange_clients = Noir::TreeSitterJavaParameterExtractor.extract_http_exchange_client_classes_from(root, content)
            visible_meta_mappings = visible_meta_annotation_mappings(path, content, package_name, meta_annotation_index)
            imports = java_imports(content)

            # The file's String-constant table is identical for every
            # route in the file, so build it once here and thread it into
            # the per-route parameter walks (and the WebSocket branches
            # below) instead of rebuilding it — a full recursive tree walk
            # — on every emitted route.
            file_constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content, java_project_constants(path))

            # Callee lookups share the file's method and declaration
            # indexes across every route, built on the first route that
            # needs them.
            file_callees = Noir::JavaCalleeExtractor::FileCallees.new(root, content, path)
            # Same for the handler-method lookups below (built on the first route).
            param_index = nil.as(Noir::TreeSitterJavaParameterExtractor::FileIndex?)
            model_attribute_methods = nil.as(Hash(String, Array(Tuple(String, Array(String))))?)

            Noir::TreeSitterJavaRouteExtractor.extract_routes_from(root, content, visible_meta_mappings, file_constants).each do |route|
              is_feign_client = feign_clients.includes?(route.class_name)
              is_http_exchange_client = http_exchange_clients.includes?(route.class_name)
              is_internal_client = is_feign_client || is_http_exchange_client

              param_index ||= Noir::TreeSitterJavaParameterExtractor.build_file_index(root, content)
              parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes_from(
                root, content, route.class_name, route.method_name, param_index
              )
              # The POST form-binding default is applied per-parameter in
              # the extractor so an explicit `@RequestBody` resolves to
              # "json" rather than inheriting "form".

              parameters = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters_from(
                root, content, route.class_name, route.method_name, route.verb, parameter_format, dto_index, route.line,
                constants: file_constants, index: param_index, injected_annotations: injected_annotations,
                converted_types: converted_types, disallowed_fields: disallowed_fields
              )
              merge_route_condition_params(parameters, route.params)

              base_path = is_internal_client ? "" : configured_base_path

              line = route.line + 1
              details = Details.new(PathInfo.new(path, line))

              endpoint = Endpoint.new(
                resolve_endpoint_path(Noir::URLPath.join_rooted(base_path, route.path), spring_properties),
                route.verb, parameters, details, is_internal_client
              )
              endpoint.route_conditions = route.params
              endpoint.handler = jvm_route_handler(route, path)

              # 1-hop callees out of the handler method body. Cross-file
              # definition resolution is intentionally out of scope —
              # `Callee#path` points at the call site, matching every
              # other analyzer's first-cut honest scope.
              if include_callee && !(route.class_name.empty? || route.method_name.empty?)
                file_callees.callees_in_method(route.class_name, route.method_name, route.line).each do |entry|
                  name, callee_path, callee_line = entry
                  endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                end
                # `@ModelAttribute` methods run before every handler of
                # their controller, so their callees (the `findById` that
                # loads the owner a handler then edits) belong to every
                # route of the class.
                model_attribute_methods ||= model_attribute_methods_by_class(root, content)
                model_attribute_methods[route.class_name]?.try &.each do |(method_name, path_variables)|
                  # A `@PathVariable` the route does not carry binds null
                  # (or fails), so the supplier's lookup does not run there:
                  # spring-petclinic's `findOwner` returns `new Owner()` on
                  # `/owners/new` and calls `findById` only under `{ownerId}`.
                  next unless path_variables.all? { |var| endpoint.url.includes?("{#{var}}") || endpoint.url.includes?("{#{var}:") }
                  file_callees.callees_in_method(route.class_name, method_name).each do |entry|
                    name, callee_path, callee_line = entry
                    endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
              end

              @result << endpoint
            end

            Noir::TreeSitterJavaRouteExtractor.extract_controller_interface_implementations_from(root, content, visible_meta_mappings, file_constants).each do |implementation|
              implementation.interface_names.each do |interface_name|
                next if implementation.paths.empty?
                # Concrete @Override that re-declares its own mapping
                # annotation shadows the interface's method-level
                # mapping (Spring closest-annotation-wins). The direct
                # scan already emitted that route — skip the duplicate.
                entries = visible_interface_routes(interface_route_index, path, package_name, imports, interface_name).reject do |entry|
                  implementation.annotated_method_names.includes?(entry.route.method_name)
                end
                entry_params = interface_route_params(entries, dto_builder, injected_annotations, converted_types)
                entries.each_with_index do |entry, entry_index|
                  entry_route = entry.route
                  implementation.paths.each do |implementation_path|
                    inherited_path = Noir::URLPath.join_rooted(implementation_path, entry_route.path)
                    parameters = entry_params[entry_index].dup
                    merge_route_condition_params(parameters, implementation.params + entry_route.params)

                    details = Details.new(PathInfo.new(entry.path, entry_route.line + 1))
                    endpoint = Endpoint.new(
                      resolve_endpoint_path(Noir::URLPath.join_rooted(configured_base_path, inherited_path), spring_properties),
                      entry_route.verb, parameters, details
                    )
                    endpoint.route_conditions = implementation.params + entry_route.params
                    # The body lives on the `@Override`, not the interface method;
                    # no override in this class, no handler.
                    param_index ||= Noir::TreeSitterJavaParameterExtractor.build_file_index(root, content)
                    if (impl_method = param_index.methods["#{implementation.class_name}##{entry_route.method_name}"]?.try(&.first?)) &&
                       (impl_row = Noir::TreeSitter.name_row(impl_method))
                      endpoint.handler = Handler.new("#{implementation.class_name}.#{entry_route.method_name}", path, impl_row + 1)
                    end

                    # The route is declared on the interface (springdoc /
                    # OpenAPI `*Api` contracts), but the behaviour — and
                    # thus the callees worth surfacing for ai-context —
                    # lives in the `@Override` method on the concrete
                    # controller currently being walked. Pull 1-hop
                    # callees from that implementing body rather than the
                    # empty interface method.
                    if include_callee && !(implementation.class_name.empty? || entry_route.method_name.empty?)
                      file_callees.callees_in_method(implementation.class_name, entry_route.method_name).each do |callee_entry|
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
              constants = file_constants
              collect_stomp_endpoints(JavaEngine.strip_comments(content), constants).each do |entry|
                endpoint_path, line = entry
                endpoint = Endpoint.new(
                  resolve_endpoint_path(Noir::URLPath.join_rooted(configured_base_path, endpoint_path), spring_properties),
                  "GET", Details.new(PathInfo.new(path, line))
                )
                endpoint.protocol = "ws"
                @result << endpoint
              end
            end

            if has_message_mapping_bindings
              constants = file_constants
              collect_message_mapping_endpoints(root, content, constants, stomp_application_prefixes).each do |entry|
                verb, destination, line = entry
                endpoint = Endpoint.new(
                  resolve_endpoint_path(destination, spring_properties),
                  verb, Details.new(PathInfo.new(path, line))
                )
                endpoint.protocol = "ws"
                @result << endpoint
              end
            end

            if has_resource_handler_bindings
              constants = file_constants
              collect_resource_handler_endpoints(content, constants).each do |entry|
                endpoint_path, line = entry
                @result << Endpoint.new(
                  resolve_endpoint_path(Noir::URLPath.join_rooted(configured_base_path, endpoint_path), spring_properties),
                  "GET", Details.new(PathInfo.new(path, line))
                )
              end
            end
          end
        else
          # Reactive routes declared via `router().route(...).andRoute(...)`
          # — regex-scoped because the builder-pattern shape isn't
          # worth a dedicated tree-sitter walk yet.
          # {verb calls, nest prefixes, offset of the block in `content`}.
          # The first two hold positions relative to the block, so the block's
          # own offset is what turns a call position into a file line.
          route_blocks = [] of Tuple(Array(RouterCall), Array(Tuple(Int32, Int32, String)), Int32)
          reactive_callees = {} of String => Array(Callee)
          # `{method name => params}` for `this::handler` references, and
          # `{block offset, call position} => params` for inline lambdas.
          handler_params = {} of String => Array(Param)
          lambda_handler_texts = {} of Tuple(Int32, Int32) => String
          lambda_handler_params = {} of Tuple(Int32, Int32) => Array(Param)
          # The block and verb-call scans are regexes: on the raw source a
          # commented-out `.andRoute(GET(...))` was a route. Offsets and
          # line numbers are kept.
          content = JavaEngine.strip_comments(content)

          # Single tree-sitter parse for the whole reactive file: the
          # constant table and the `this::handler` callee resolution both
          # read from this one `root`, so the file isn't parsed twice
          # when callees are requested (and constants are resolved once,
          # not once-per-block).
          Noir::TreeSitter.parse_java(content) do |root|
            # Every non-annotation `.java` file lands here; only router
            # files are worth seeding (a copy of) the project table into.
            project_constants = content_matches?(content, REGEX_ROUTER_CODE_BLOCK) ? java_project_constants(path) : nil
            constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content, project_constants)
            each_router_block(content) do |method_code, block_offset|
              # Pick up `nest(RequestPredicates.path("/prefix"), ...)`
              # / `nest(path("/prefix"), ...)` byte ranges so verb
              # calls inside the nested lambda get the prefix added.
              # Servlet-fn and WebFlux both use this idiom heavily;
              # without prefix awareness routes like
              # `route().nest(path("/product"), builder ->
              # builder.GET("/name/{name}", ...))` surfaced as
              # `GET /name/{name}` instead of `GET /product/name/{name}`.
              calls = collect_router_route_calls(method_code, constants)
              route_blocks << {calls, collect_nest_prefixes(method_code, constants), block_offset}
              calls.each do |call|
                next unless lambda = call[5]
                lambda_handler_texts[{block_offset, call[0]}] = lambda
              end
            end

            wanted = Set(String).new
            route_blocks.each { |calls, _, _| calls.each { |call| wanted << call[3] unless call[3].empty? } }
            # Resolve same-file `this::handler` method bodies to 1-hop
            # callees so reactive endpoints carry handler context too.
            reactive_callees = build_reactive_method_callees(root, content, path, wanted) if include_callee
            # ...and to the request inputs they read off `ServerRequest`.
            unless wanted.empty? && lambda_handler_texts.empty?
              dto_index = dto_builder.build_for_with_root(path, content, root)
              handler_params = reactive_handler_params(root, content, wanted, dto_index)
              lambda_handler_texts.each { |key, handler| lambda_handler_params[key] = server_request_params(handler, dto_index) }
            end
          end

          route_blocks.each do |calls, nest_prefixes, block_offset|
            calls.each do |call|
              pos, method, endpoint, handler_ref, verb_pos, _ = call
              nest_prefix = ""
              nest_prefixes.each do |start_b, end_b, prefix|
                if pos >= start_b && pos < end_b
                  nest_prefix = Noir::URLPath.join_rooted(nest_prefix, prefix)
                end
              end
              composed = nest_prefix.empty? ? endpoint : Noir::URLPath.join_rooted(nest_prefix, endpoint)
              details = Details.new(PathInfo.new(path, line_number_for_index(content, block_offset + verb_pos)))
              reactive_endpoint = Endpoint.new(
                resolve_endpoint_path(Noir::URLPath.join_rooted(configured_base_path, composed), spring_properties),
                method, details
              )

              if include_callee && !handler_ref.empty?
                if handler_callees = reactive_callees[handler_ref]?
                  handler_callees.each { |callee| reactive_endpoint.push_callee(callee) }
                end
              end

              request_params = handler_ref.empty? ? lambda_handler_params[{block_offset, pos}]? : handler_params[handler_ref]?
              if request_params
                request_params.each { |param| reactive_endpoint.push_param(param) }
              end

              @result << reactive_endpoint
            end
          end
        end
      end

      path_configs.each do |root, config|
        @result.concat(spring_provided_endpoints(root, spring_property_maps[root], config.web_base_path))
      end
      Fiber.yield

      @result
    end

    # Build path configs, STOMP destination prefixes, meta-annotation index,
    # and interface-route index for the pre-filtered `.java` source set.
    #
    # Path roots + STOMP + meta annotations share one content walk and at
    # most one tree-sitter parse per file (previously three independent
    # passes). Interface routes need a complete meta index, so they run as
    # a second pass over the same cached content.
    private def build_spring_indexes(java_files : Array(String)) : Tuple(
      Hash(String, SpringPathConfig),
      Hash(String, Hash(String, String)),
      Hash(String, Array(String)),
      SpringMetaAnnotationIndex,
      SpringInterfaceRouteIndex,
      Hash(String, Set(String)),
      Hash(String, Set(String)),
      Hash(String, Array(String)),
    )
      path_configs = Hash(String, SpringPathConfig).new
      spring_property_maps = Hash(String, Hash(String, String)).new
      stomp_prefixes = Hash(String, Array(String)).new
      meta_index = SpringMetaAnnotationIndex.new
      # Per project root: `@interface` names meta-annotated with an injected
      # argument annotation (`@CurrentMember` carrying `@AuthenticationPrincipal`).
      # ponytail: keyed by simple name project-wide, not by import visibility.
      injected_annotations = Hash(String, Set(String)).new
      # Per project root: types a registered `Formatter`/`Converter` builds
      # from one request value, so a nested field of that type stays scalar.
      converted_types = Hash(String, Set(String)).new
      # Per project root: fields a `@ControllerAdvice` `@InitBinder` disallows for every controller.
      advice_disallowed = Hash(String, Array(String)).new
      project_roots = Set(String).new

      java_files.each do |path|
        project_root = project_root_for(path)
        project_roots << project_root

        content = read_file_content(path)
        if content.includes?("implements")
          content.scan(CONVERTER_TARGET_RE) { |match| (converted_types[project_root] ||= Set(String).new) << match[1] }
        end
        if content.includes?("ControllerAdvice")
          fields = disallowed_binder_fields(content)
          (advice_disallowed[project_root] ||= [] of String).concat(fields) unless fields.empty?
        end
        # One union pass rejects the files that can feed neither index
        # before the two individual scans run.
        needs_injected = content_matches?(content, META_ANNOTATION_RE) && content_matches?(content, INJECTED_META_RE)
        next unless needs_injected || content_matches?(content, SPRING_INDEX_PRESCREEN_RE)
        needs_stomp = content_matches?(content, STOMP_PREFIX_RE)
        needs_meta = content_matches?(content, SPRING_WEB_BIND_RE) && content_matches?(content, META_ANNOTATION_RE)
        next unless needs_stomp || needs_meta || needs_injected

        Noir::TreeSitter.parse_java(content) do |root|
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content, java_project_constants(path))

          if needs_stomp
            collected = collect_stomp_application_prefixes(content, constants)
            unless collected.empty?
              stomp_prefixes[project_root] ||= [] of String
              stomp_prefixes[project_root].concat(collected)
              stomp_prefixes[project_root] = stomp_prefixes[project_root].uniq
            end
          end

          if needs_meta
            package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
            Noir::TreeSitterJavaRouteExtractor.extract_meta_mappings_from(root, content, constants).each do |name, mapping|
              meta_index.add(project_root, configured_base_for(path), package_name, name, mapping)
            end
          end

          if needs_injected
            names = Noir::TreeSitterJavaParameterExtractor.extract_injected_annotation_types_from(root, content)
            (injected_annotations[project_root] ||= Set(String).new).concat(names) unless names.empty?
          end
        end
      end

      project_roots.each do |root|
        values = spring_config_values_for(root)
        spring_property_maps[root] = values
        path_configs[root] = SpringPathConfig.new(
          normalize_optional_path(values["server.servlet.context-path"]?),
          normalize_optional_path(values["spring.webflux.base-path"]?)
        )
      end

      interface_index = collect_interface_route_index(java_files, meta_index)
      {path_configs, spring_property_maps, stomp_prefixes, meta_index, interface_index, injected_annotations, converted_types, advice_disallowed}
    end

    private def collect_interface_route_index(java_files : Array(String),
                                              meta_annotation_index : SpringMetaAnnotationIndex) : SpringInterfaceRouteIndex
      index = SpringInterfaceRouteIndex.new

      # `java_files` is already extension-filtered and test-path-free.
      java_files.each do |path|
        content = read_file_content(path)
        # Inheritable routes come from Java interfaces (Feign, Spring HTTP
        # Interface, OpenAPI-style `*Api`) and from `abstract` base
        # classes that concrete controllers extend. Files with neither
        # keyword — the bulk of controller classes — can't contribute, so
        # skip the parse before the annotation gate below.
        next unless content_matches?(content, INTERFACE_OR_ABSTRACT_RE)
        next unless content_matches?(content, INTERFACE_ROUTE_MARKER_RE)

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          visible_meta_mappings = visible_meta_annotation_mappings(path, content, package_name, meta_annotation_index)
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content, java_project_constants(path))
          Noir::TreeSitterJavaRouteExtractor.extract_interface_routes_from(root, content, visible_meta_mappings, constants).each do |interface_name, routes|
            routes.each do |route|
              index.add(project_root_for(path), package_name, interface_name, SpringInterfaceRouteEntry.new(route, path, content, package_name))
            end
          end
        end
      end

      index
    end

    private def visible_meta_annotation_mappings(path : String,
                                                 content : String,
                                                 package_name : String,
                                                 index : SpringMetaAnnotationIndex) : Hash(String, SpringRouteMapping)
      mappings = Hash(String, SpringRouteMapping).new
      imports = java_imports(content)
      on_demand, single_type = imports.partition(&.ends_with?(".*"))
      # The module's own declarations before the rest of the scan base; the
      # first entry for a name wins, so the order below is Java's: a
      # single-type import, then the same package, then on-demand imports.
      scopes = {project_root_for(path), "base:#{configured_base_for(path)}"}
      single_type.each do |import_name|
        scopes.each do |scope|
          if mapping = index.by_fqcn[{scope, import_name}]?
            mappings[import_name.split('.').last] ||= mapping
          end
        end
      end
      scopes.each { |scope| merge_meta_package(mappings, index.by_package[{scope, package_name}]?) }
      on_demand.each do |import_name|
        scopes.each { |scope| merge_meta_package(mappings, index.by_package[{scope, import_name[...-2]}]?) }
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

    # Handler parameters of each inherited interface route, aligned with
    # `entries`. Each interface file is parsed (and DTO/method-indexed)
    # once, not once per route: a 500-method `*Api` interface used to be
    # re-parsed 500 times.
    private def interface_route_params(entries : Array(SpringInterfaceRouteEntry),
                                       dto_builder : Noir::TreeSitterJavaDtoIndex,
                                       injected_annotations : Set(String)?,
                                       converted_types : Set(String)?) : Array(Array(Param))
      result = Array(Array(Param)).new(entries.size) { [] of Param }
      indexes_by_path = Hash(String, Array(Int32)).new { |hash, key| hash[key] = [] of Int32 }
      entries.each_with_index { |entry, i| indexes_by_path[entry.path] << i }

      indexes_by_path.each do |entry_path, indexes|
        source = entries[indexes.first].source
        Noir::TreeSitter.parse_java(source) do |interface_root|
          dto_index = with_default_json_naming(dto_builder.build_for_with_root(entry_path, source, interface_root), entry_path)
          param_index = Noir::TreeSitterJavaParameterExtractor.build_file_index(interface_root, source)
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(interface_root, source)
          indexes.each do |i|
            route = entries[i].route
            # POST form-binding default applied per-parameter in the
            # extractor (keeps `@RequestBody` as "json").
            parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes_from(
              interface_root, source, route.class_name, route.method_name, param_index
            )
            result[i] = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters_from(
              interface_root, source, route.class_name, route.method_name,
              route.verb, parameter_format, dto_index, route.line, constants: constants, index: param_index,
              injected_annotations: injected_annotations, converted_types: converted_types
            )
          end
        end
      end
      result
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

    # WebSocket handshake paths: STOMP's `addEndpoint(String...)` and plain
    # `WebSocketHandlerRegistry.addHandler(handler, String...)`, whose first
    # argument is the handler. `content` comes with comments blanked, so a
    # commented-out registration is not read.
    private def collect_stomp_endpoints(content : String,
                                        constants : Hash(String, String)) : Array(Tuple(String, Int32))
      endpoints = [] of Tuple(String, Int32)
      {"addEndpoint", "addHandler"}.each do |name|
        offset = 0
        while marker = content.index(name, offset)
          offset = marker + name.size
          next unless method_call_name?(content, marker, name.size)

          open_idx = content.index('(', marker)
          next unless open_idx
          close_idx = find_matching_paren(content, open_idx)
          next unless close_idx

          args = top_level_arguments(content[(open_idx + 1)...close_idx])
          args = args[1..]? || [] of String if name == "addHandler"
          line = line_number_for_index(content, marker)
          args.each do |arg|
            if endpoint_path = resolve_router_path(arg, constants)
              endpoints << {endpoint_path, line}
            end
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
        line = line_number_for_index(content, marker)
        top_level_arguments(args).each do |arg|
          resource_handler_patterns(arg, content, constants).each { |pattern| endpoints << {pattern, line} }
        end
      end

      endpoints.uniq
    end

    # `addResourceHandler(String...)` arguments: a path, a `new String[]{...}`
    # / `{...}` array, or a `String[]` constant declared in this file.
    #
    # ponytail: array constants from other classes are not resolved.
    private def resource_handler_patterns(arg : String, content : String, constants : Hash(String, String)) : Array(String)
      if path = resolve_router_path(arg, constants)
        return [path]
      end
      elements = arg.match(/\{(.*)\}\s*\z/m).try(&.[1])
      if elements.nil? && arg.matches?(/\A[\w.]+\z/)
        name = Regex.escape(arg.split('.').last)
        elements = content.match(/\bString\s*\[\s*\]\s+#{name}\s*=\s*(?:new\s+String\s*\[\s*\]\s*)?\{([^}]*)\}/).try(&.[1])
      end
      return [] of String unless elements
      top_level_arguments(elements).compact_map { |element| resolve_router_path(element, constants) }
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
            prefixes << Noir::URLPath.join_rooted(outer_prefix, class_path)
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
              endpoints << {verb, Noir::URLPath.join_rooted(application_prefix, Noir::URLPath.join_rooted(class_prefix, path)), line + 1}
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

    private def method_call_name?(code : String, marker : Int32, name_size : Int32) : Bool
      before = marker.zero? ? '\0' : code[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_'

      after_idx = marker + name_size
      while after_idx < code.size && code[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < code.size && code[after_idx] == '('
    end

    private def disallowed_binder_fields(content : String) : Array(String)
      fields = [] of String
      return fields unless content.includes?("setDisallowedFields")
      content.scan(DISALLOWED_FIELDS_RE) do |call|
        call[1].scan(/"([^"]*)"/) { |literal| fields << literal[1] }
      end
      fields
    end

    # The method-level `@ModelAttribute` methods of every class in the
    # file, each with the `@PathVariable` names it binds: Spring runs them
    # before each handler of that class.
    private def model_attribute_methods_by_class(root : LibTreeSitter::TSNode,
                                                 content : String) : Hash(String, Array(Tuple(String, Array(String))))
      by_class = Hash(String, Array(Tuple(String, Array(String)))).new
      Noir::JavaCalleeExtractor.build_method_index(root, content).each do |(class_name, method_name), nodes|
        next unless node = nodes.find { |candidate| java_annotated?(candidate, content, "ModelAttribute") }
        (by_class[class_name] ||= [] of Tuple(String, Array(String))) << {method_name, java_path_variables(node, content)}
      end
      by_class
    end

    # `@PathVariable("id")` / `@PathVariable(name = "id")` name the
    # variable; a bare `@PathVariable Long id` binds the parameter name.
    private def java_path_variables(method : LibTreeSitter::TSNode, content : String) : Array(String)
      variables = [] of String
      return variables unless params = Noir::TreeSitter.field(method, "parameters")
      Noir::TreeSitter.each_named_child(params) do |param|
        each_java_annotation(param, content) do |name, args, _|
          next unless name == "PathVariable"
          explicit = args.try { |node| Noir::TreeSitter.node_text(node, content).match(/\A\(\s*(?:(?:name|value)\s*=\s*)?"([^"]+)"/).try(&.[1]) }
          if variable = explicit || Noir::TreeSitter.field(param, "name").try { |node| Noir::TreeSitter.node_text(node, content) }
            variables << variable
          end
        end
      end
      variables
    end

    private def java_annotated?(decl : LibTreeSitter::TSNode, content : String, wanted : String) : Bool
      each_java_annotation(decl, content) { |name, _, _| return true if name == wanted }
      false
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
    # {match position, verb, path, handler method name, verb position,
    #  inline lambda handler text}.
    alias RouterCall = Tuple(Int32, String, String, String, Int32, String?)

    private def collect_router_route_calls(code : String,
                                           constants : Hash(String, String)) : Array(RouterCall)
      calls = [] of RouterCall

      code.scan(REGEX_ROUTE_CALL) do |match|
        open_idx = (match.end || 0) - 1
        next if open_idx < 0
        close_idx = find_matching_paren(code, open_idx)
        next unless close_idx

        args = code[(open_idx + 1)...close_idx]
        arg_list = top_level_arguments(args)
        first_arg = arg_list.first? || ""
        # Builder `.GET(h::list)` / `.POST(req -> …)` has no pattern of its
        # own: it matches the enclosing `path(...)` / `nest(...)` prefix.
        path_less = first_arg.includes?("::") || first_arg.includes?("->")
        # `.GET(path("/x").and(accept(...)), h)` puts the pattern in a
        # predicate, like `nest(path("/x"), ...)`.
        path = path_less ? "" : (resolve_router_path(first_arg, constants) || path_predicate_prefix(first_arg, constants))
        next unless path

        # The handler is the second argument of `.GET("/x", this::handle)`
        # / `route(RequestPredicates.GET("/x"), this::handle)`. Capture a
        # same-file method-reference name so the reactive branch can pull
        # 1-hop callees out of that handler body (WebFlux/servlet-fn
        # RouterFunction handlers carry the real behaviour worth surfacing
        # for ai-context).
        handler_arg = path_less ? first_arg : arg_list[1]?
        if handler_arg.nil? && match[1] != "."
          outer_open = (match.end(1) || 0) - 1
          if outer_close = find_matching_paren(code, outer_open)
            handler_arg = top_level_arguments(code[(outer_open + 1)...outer_close])[1]?
          end
        end
        handler_ref = handler_arg ? handler_method_reference(handler_arg) : ""
        # Two positions: the match start decides which `nest(...)` range the
        # call sits in, while the verb is where the route itself is written —
        # `.route(\n  GET("/hello")` declares the route on the `GET` line, not
        # on the `route(` line that opens the statement.
        lambda = handler_arg if handler_arg && handler_ref.empty? && handler_arg.includes?("->")
        calls << {match.begin || 0, match[2], path.gsub(/\n/, ""), handler_ref, match.begin(2) || match.begin || 0, lambda}
      end

      calls
    end

    # Each router statement in `code` with its offset: from a
    # `ROUTER_BLOCK_START_RE` match to the `;` that ends the statement at
    # depth 0 (or the `}` closing the enclosing block). A statement inside
    # a block lambda (`request -> { ...; }`) does not end it.
    #
    # A statement with no verb call of its own (`Builder b = route();`)
    # holds a builder the following `b.GET(...)` statements fill, so its
    # block runs to the end of the enclosing `{ }` instead.
    #
    # Works in byte offsets (every delimiter is ASCII, and UTF-8 never
    # reuses ASCII bytes); the char offset handed to the block is counted
    # incrementally, so a non-ASCII file is not re-indexed per block.
    private def each_router_block(code : String, & : String, Int32 ->) : Nil
      bytes = code.to_slice
      offset = 0
      char_offset = 0
      counted_to = 0
      while match = ROUTER_BLOCK_START_RE.match_at_byte_index(code, offset)
        start = match.byte_begin(0)
        open = match.byte_end(0) - 1
        stop = router_statement_end(bytes, open, true)
        if !code.byte_slice(start, stop - start).matches?(REGEX_ROUTE_CALL)
          stop = router_statement_end(bytes, open, false)
        end
        char_offset += utf8_char_count(bytes, counted_to, start)
        counted_to = start
        yield code.byte_slice(start, stop - start), char_offset
        offset = stop
      end
    end

    private def utf8_char_count(bytes : Bytes, from : Int32, to : Int32) : Int32
      count = 0
      (from...to).each { |index| count += 1 unless bytes[index] & 0xC0 == 0x80 }
      count
    end

    # Byte offset just past the statement that opens at `from`: its `;` at
    # depth 0, or the `}` closing the enclosing block (also where it ends
    # when `at_semicolon` is false).
    private def router_statement_end(bytes : Bytes, from : Int32, at_semicolon : Bool) : Int32
      depth = 0
      index = from
      while index < bytes.size
        byte = bytes[index]
        case byte
        when '"'.ord, '\''.ord
          index += 1
          while index < bytes.size && bytes[index] != byte
            index += 1 if bytes[index] == '\\'.ord
            index += 1
          end
        when '('.ord, '['.ord, '{'.ord
          depth += 1
        when ')'.ord, ']'.ord, '}'.ord
          depth -= 1
          return index if depth < 0
        when ';'.ord
          return index + 1 if depth.zero? && at_semicolon
        end
        index += 1
      end
      bytes.size
    end

    SERVER_REQUEST_PARAM_RE  = /\b(\w+)\s*\.\s*(queryParam|param)\s*\(\s*"([^"]+)"/
    SERVER_REQUEST_HEADER_RE = /\b(\w+)\s*\.\s*headers\s*\(\s*\)\s*\.\s*(?:firstHeader|header)\s*\(\s*"([^"]+)"/
    SERVER_REQUEST_BODY_RE   = /\b(\w+)\s*\.\s*(?:bodyToMono|bodyToFlux|body)\s*\(\s*([\w.]+)\s*\.\s*class\b/
    LAMBDA_RECEIVER_RE       = /\A\(?\s*(?:[\w.<>]+\s+)?(\w+)\s*\)?\s*->/

    # `{method name => params}` for the wanted same-file handler methods:
    # what each reads off its `ServerRequest` parameter.
    private def reactive_handler_params(root : LibTreeSitter::TSNode,
                                        content : String,
                                        wanted : Set(String),
                                        dto_index : Noir::TreeSitterJavaDtoIndex::Index) : Hash(String, Array(Param))
      result = {} of String => Array(Param)
      # `users::get` / `orders::get` in one file: the bare name cannot say
      # which `get` a route uses, so neither lends its inputs.
      ambiguous = Set(String).new
      walk_reactive_method_declarations(root) do |method|
        name_node = Noir::TreeSitter.field(method, "name")
        next unless name_node
        method_name = Noir::TreeSitter.node_text(name_node, content)
        next unless wanted.includes?(method_name)
        if result.has_key?(method_name)
          ambiguous << method_name
          next
        end

        receiver = nil
        if parameters = Noir::TreeSitter.field(method, "parameters")
          Noir::TreeSitter.each_named_child(parameters) do |param|
            next unless receiver.nil? && Noir::TreeSitter.node_type(param) == "formal_parameter"
            type_node = Noir::TreeSitter.field(param, "type")
            param_name = Noir::TreeSitter.field(param, "name")
            next unless type_node && param_name
            next unless Noir::TreeSitter.node_text(type_node, content).ends_with?("ServerRequest")
            receiver = Noir::TreeSitter.node_text(param_name, content)
          end
        end
        body = Noir::TreeSitter.field(method, "body")
        unless receiver && body
          result[method_name] = [] of Param
          next
        end
        result[method_name] = server_request_params(Noir::TreeSitter.node_text(body, content), dto_index, receiver)
      end
      ambiguous.each { |name| result.delete(name) }
      result
    end

    # Query, header and JSON body inputs `receiver` reads in `code`
    # (`r.queryParam("q")`, `r.headers().firstHeader("X")`,
    # `r.bodyToMono(Dto.class)`). Without a receiver, `code` is an inline
    # `request -> ...` lambda and its parameter is the receiver.
    private def server_request_params(code : String,
                                      dto_index : Noir::TreeSitterJavaDtoIndex::Index,
                                      receiver : String? = nil) : Array(Param)
      params = [] of Param
      receiver ||= code.match(LAMBDA_RECEIVER_RE).try(&.[1])
      return params unless receiver

      code.scan(SERVER_REQUEST_PARAM_RE) do |match|
        params << Param.new(match[3], "", "query") if match[1] == receiver
      end
      code.scan(SERVER_REQUEST_HEADER_RE) do |match|
        params << Param.new(match[2], "", "header") if match[1] == receiver
      end
      code.scan(SERVER_REQUEST_BODY_RE) do |match|
        next unless match[1] == receiver
        next unless fields = dto_index[match[2].split('.').last]?
        fields.each { |field| params << Param.new(field.json_name, "", "json") unless field.json_ignored? }
      end
      params
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

      # `nest(path("/p"), …)` / `.andNest(path("/p"), …)` carry the prefix
      # in a predicate; the builder's `.path("/p", b -> …)` carries it as a
      # plain first argument.
      code.scan(NEST_CALL_RE) do |match|
        open_idx = (match.end || 0) - 1
        close_idx = find_matching_paren(code, open_idx)
        next unless close_idx

        args = code[(open_idx + 1)...close_idx]
        predicate = first_argument(args)
        prefix = if match[1]?
                   path_predicate_prefix(predicate, constants)
                 elsif args.includes?("->")
                   resolve_router_path(predicate, constants)
                 end
        next unless prefix

        regions << {open_idx, close_idx, prefix}
      end

      regions
    end

    NEST_CALL_RE = /(?<![\w$])(?:(nest|andNest)|(?<=\.)path)\s*\(/

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
      args = JavaEngine.strip_comments(args)
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

    # `Rules::JAVA` minus the single-quote quote style, and dropping EVERY
    # empty part rather than only a trailing one — the old body ended in
    # `.map(&.strip).reject(&.empty?)`, so `"a" + + "b"` yielded two terms, not
    # three. Both matter to the caller, which concatenates the terms it gets
    # back into a route path. File-local because spring is the only splitter
    # with this combination.
    SPLIT_CONCAT_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace,
      quotes: "\"",
      escape: Noir::TopLevelSplit::Escape::InQuotes,
      strip: true,
      empties: Noir::TopLevelSplit::Empties::DropAll,
      per_kind: false,
      clamp: true,
    )

    private def split_top_level_concat(expression : String) : Array(String)
      Noir::TopLevelSplit.split(expression, '+', SPLIT_CONCAT_RULES)
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
      JavaEngine.each_char_after(code, open_idx) do |c, i|
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
      values = spring_config_values_for(project_root)
      SpringPathConfig.new(
        normalize_optional_path(values["server.servlet.context-path"]?),
        normalize_optional_path(values["spring.webflux.base-path"]?)
      )
    end

    private def resolve_endpoint_path(path : String, properties : Hash(String, String)) : String
      SpringPropertyPath.resolve(path, properties)
    end
  end
end
