require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./kotlin_callee_extractor"

module Noir
  # Tree-sitter-backed Ktor DSL route extractor.
  #
  # Walks the canonical Ktor server idiom:
  #
  # ```
  # routing {
  #   get("/x") { ... }
  #   route("/api") {
  #     post("/items") { val item = call.receive < Item > () }
  #   }
  #   authenticate("auth-jwt") {
  #     get("/profile") { ... }
  #   }
  # }
  # ```
  #
  # Recognises:
  #
  #   * Verb DSL calls — `get`/`post`/`put`/`delete`/`patch`/`head`/`options`
  #     with a string-literal path argument and a trailing lambda body.
  #   * `route("/x") { ... }` blocks contributing to the path prefix.
  #   * `authenticate("realm") { ... }` blocks acting as transparent
  #     wrappers (no prefix change). Tagging is handled elsewhere; we
  #     just descend so wrapped routes are still discovered.
  #   * `routing { ... }` and `application.routing { ... }` entry points.
  #   * Type-safe `@Resource` routing — `get<VideoStream> { }`,
  #     `resource<Login> { post { } }`, `method(HttpMethod.Get) { handle<T> }` —
  #     with cross-file parent-path composition.
  #   * Inside each verb's lambda body:
  #     - `call.receive<T>()` → `body` parameter typed `T` as `json`
  #     - `call.parameters["name"]` → `name` parameter as `query`
  #     - `call.request.headers["name"]` → `name` parameter as `header`
  #
  # Not covered yet:
  #
  #   * `install(plugin) { ... }` plugin scoping that affects routing.
  module TreeSitterKotlinKtorRouteExtractor
    extend self

    HTTP_VERB_NAMES = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      # WebSocket / SSE handlers are registered with the same path +
      # trailing-lambda DSL as the HTTP verbs. The connection opens with
      # a GET (the WebSocket upgrade / SSE stream are both GET requests),
      # so surface them as GET routes rather than dropping them.
      "webSocket"    => "GET",
      "webSocketRaw" => "GET",
      "sse"          => "GET",
    }

    # Pass-through DSL calls — descend into their lambda body without
    # changing the path prefix. `routing` is the entry point;
    # `authenticate` wraps a sub-tree behind an auth realm; the
    # remaining names cover the common Ktor scoping helpers. `install`
    # is handled separately (see `walk`) because only `install(Routing)`
    # contributes routes — every other plugin config block must NOT be
    # walked as routing.
    PASSTHROUGH_NAMES = Set{
      "routing",
      "authenticate",
      "rateLimit",
      "intercept",
      "host",
      "port",
    }

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32 # 0-based line of the verb call
      getter receive_type : String?
      getter? has_body : Bool
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter form_params : Array(String)
      # 1-hop callees out of the handler lambda body. `path` is left
      # for the caller to fill in (the route extractor doesn't carry
      # the file path itself); each tuple is (callee_name, line_1_based).
      getter callees : Array(Tuple(String, Int32))

      def initialize(@verb, @path, @line, @receive_type, @has_body, @query_params, @header_params, @form_params, @callees)
      end
    end

    # A `@Resource`-annotated class collected from a single file, before
    # cross-class path composition. `lexical_name` is the dotted name as
    # it would be referenced (`Articles.New`); `ctor_param_types` are the
    # simple type names of its primary-constructor properties, one of
    # which (when it names another resource, e.g. `root: Root` /
    # `parent: ArticlesResource`) is the path-composition parent.
    struct RawResource
      getter simple_name : String
      getter lexical_name : String
      getter own_path : String
      getter ctor_param_types : Array(String)

      def initialize(@simple_name, @lexical_name, @own_path, @ctor_param_types)
      end
    end

    def extract_routes(source : String,
                       string_constants = Hash(String, String).new,
                       resource_paths = Hash(String, String).new,
                       *, include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      local_string_constants = extract_string_constants(source)
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk(root, source, "", routes, string_constants, local_string_constants, 0, include_callees, false, resource_paths)
      end
      routes
    end

    # Blank out string/char literal contents (keeping the quotes) so structural
    # brace counting ignores braces that live inside a string value.
    private def structural_only(line : String) : String
      line.gsub(/"(?:[^"\\]|\\.)*"/, %("")).gsub(/'(?:[^'\\]|\\.)*'/, "''")
    end

    def extract_string_constants(source : String) : Hash(String, String)
      constants = Hash(String, String).new
      package_name = ""
      current_type = ""
      current_depth = 0

      source.each_line do |line|
        if package_name.empty?
          if match = line.match(/^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)/)
            package_name = match[1]
          end
        end

        if match = line.match(/^\s*(?:class|object|interface)\s+([A-Za-z_][A-Za-z0-9_]*)/)
          current_type = match[1]
          current_depth = 0
        end

        if match = line.match(/\b(?:const\s+)?val\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*String)?\s*=\s*"([^"]*)"/)
          name = match[1]
          value = match[2]
          constants[name] ||= value
          unless current_type.empty?
            constants["#{current_type}.#{name}"] ||= value
            constants["#{package_name}.#{current_type}.#{name}"] ||= value unless package_name.empty?
          end
        end

        unless current_type.empty?
          # Count braces on a string-blanked copy so a `}` inside a const string
          # value (regex/JSON/template) can't close the enclosing type early.
          structural = structural_only(line)
          current_depth += structural.count("{")
          current_depth -= structural.count("}")
          if current_depth <= 0 && structural.includes?("}")
            current_type = ""
            current_depth = 0
          end
        end
      end

      constants
    end

    # ---- type-safe resource routing ----------------------------------

    # Collect every `@Resource("path")`-annotated class/object in a file
    # (including nested ones, with their dotted lexical name). The
    # analyzer gathers these across the whole project before composing
    # full paths, since a resource's parent is often declared in another
    # module (Ktor's KMP `commonMain` resource definitions).
    def extract_resource_classes(source : String) : Array(RawResource)
      result = [] of RawResource
      Noir::TreeSitter.parse_kotlin(source) do |root|
        collect_resource_classes(root, source, "", result, 0)
      end
      result
    end

    # Resolve each raw resource to its full URL path. The parent is the
    # first primary-constructor property whose type is itself a resource
    # (`root: Root` → `/api`); the child path joins onto it. Returns a
    # map keyed by BOTH the dotted lexical name (`Articles.New`) and the
    # bare simple name (`TagsResource`) so `get<...>` references resolve
    # either way.
    def compose_resource_paths(raws : Array(RawResource)) : Hash(String, String)
      by_simple = Hash(String, RawResource).new
      raws.each { |r| by_simple[r.simple_name] ||= r }

      result = Hash(String, String).new
      raws.each do |r|
        full = compose_full_path(r, by_simple, Set(String).new, 0)
        next if full.empty?
        result[r.lexical_name] = full
        result[r.simple_name] ||= full
      end
      result
    end

    private def compose_full_path(r : RawResource,
                                  by_simple : Hash(String, RawResource),
                                  visiting : Set(String),
                                  depth : Int32) : String
      return r.own_path if depth > Noir::TreeSitter::MAX_AST_DEPTH
      return r.own_path if visiting.includes?(r.lexical_name)
      visiting.add(r.lexical_name)

      parent_path = ""
      r.ctor_param_types.each do |t|
        next if t == r.simple_name
        if parent = by_simple[t]?
          parent_path = compose_full_path(parent, by_simple, visiting, depth + 1)
          break
        end
      end

      visiting.delete(r.lexical_name)
      parent_path.empty? ? r.own_path : join_paths(parent_path, r.own_path)
    end

    private def collect_resource_classes(node : LibTreeSitter::TSNode,
                                         source : String,
                                         lexical_prefix : String,
                                         sink : Array(RawResource),
                                         depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      ty = Noir::TreeSitter.node_type(node)

      if ty == "class_declaration" || ty == "object_declaration"
        add_resource_class(node, source, lexical_prefix, sink, depth, nil)
        return
      end

      # Iterate the children, carrying a "detached" @Resource path.
      # tree-sitter-kotlin occasionally mis-parses an `@Resource("/p")`
      # that sits behind certain leading comments as a standalone
      # `prefix_expression` sibling, leaving the class that immediately
      # follows it without its `modifiers`/annotation. We pair the
      # orphaned path with that bare class so the resource still resolves
      # (see the youkube sample / the extractor spec). Comments between
      # the two are transparent; anything else clears the carry.
      pending : String? = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        cty = Noir::TreeSitter.node_type(child)
        if cty == "class_declaration" || cty == "object_declaration"
          add_resource_class(child, source, lexical_prefix, sink, depth + 1, pending)
          pending = nil
        elsif dp = detached_resource_path(child, source)
          pending = dp
        elsif cty == "multiline_comment" || cty == "line_comment"
          # transparent — keep the carried path
        else
          pending = nil
          collect_resource_classes(child, source, lexical_prefix, sink, depth + 1)
        end
      end
    end

    # Record a `@Resource`-annotated class (resolving its own annotation,
    # or `fallback_path` when tree-sitter detached the annotation), then
    # descend into its body for nested resource classes.
    private def add_resource_class(node : LibTreeSitter::TSNode,
                                   source : String,
                                   lexical_prefix : String,
                                   sink : Array(RawResource),
                                   depth : Int32,
                                   fallback_path : String?)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      name = resource_class_name(node, source)
      return if name.empty?
      lexical = lexical_prefix.empty? ? name : "#{lexical_prefix}.#{name}"
      if own = (resource_annotation_path(node, source) || fallback_path)
        sink << RawResource.new(name, lexical, own, ctor_param_type_names(node, source))
      end
      if body = resource_class_body(node)
        collect_resource_classes(body, source, lexical, sink, depth + 1)
      end
    end

    # Recognise a `@Resource("/path")` that tree-sitter-kotlin mis-parsed
    # as a standalone `(prefix_expression (annotation (user_type Resource))
    # (parenthesized_expression (string_literal …)))` node — the
    # annotation detached from the class that follows. Returns the path,
    # or nil for any other node.
    private def detached_resource_path(node : LibTreeSitter::TSNode, source : String) : String?
      return unless Noir::TreeSitter.node_type(node) == "prefix_expression"
      ann : LibTreeSitter::TSNode? = nil
      paren : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(node) do |c|
        case Noir::TreeSitter.node_type(c)
        when "annotation"               then ann = c
        when "parenthesized_expression" then paren = c
        end
      end
      a = ann
      p = paren
      return unless a && p

      is_resource = false
      Noir::TreeSitter.each_named_child(a) do |c|
        if Noir::TreeSitter.node_type(c) == "user_type"
          is_resource = simple_type_name(Noir::TreeSitter.node_text(c, source)) == "Resource"
        end
      end
      return unless is_resource

      result : String? = nil
      Noir::TreeSitter.each_named_child(p) do |c|
        result = decode_string_literal(c, source) if Noir::TreeSitter.node_type(c) == "string_literal"
      end
      result
    end

    private def resource_class_name(decl : LibTreeSitter::TSNode, source : String) : String
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "type_identifier"
      end
      ""
    end

    private def resource_class_body(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        child = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        return child if Noir::TreeSitter.node_type(child) == "class_body"
      end
      nil
    end

    # `@Resource("/x")` → `/x`. The annotation parses as a `modifiers`
    # child carrying an `annotation` whose `constructor_invocation` pairs
    # the `Resource` user_type with a `value_arguments` holding the path
    # string. Returns nil when the class has no `@Resource`.
    private def resource_annotation_path(decl : LibTreeSitter::TSNode, source : String) : String?
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        mods = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        next unless Noir::TreeSitter.node_type(mods) == "modifiers"
        Noir::TreeSitter.each_named_child(mods) do |ann|
          next unless Noir::TreeSitter.node_type(ann) == "annotation"
          Noir::TreeSitter.each_named_child(ann) do |sub|
            next unless Noir::TreeSitter.node_type(sub) == "constructor_invocation"
            ann_name = ""
            args : LibTreeSitter::TSNode? = nil
            Noir::TreeSitter.each_named_child(sub) do |c|
              case Noir::TreeSitter.node_type(c)
              when "user_type"
                ann_name = simple_type_name(Noir::TreeSitter.node_text(c, source))
              when "value_arguments"
                args = c
              end
            end
            if ann_name == "Resource" && (a = args)
              if path = first_string_in_arguments(a, source)
                return path
              end
            end
          end
        end
      end
      nil
    end

    private def first_string_in_arguments(args : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          return decode_string_literal(child, source) if Noir::TreeSitter.node_type(child) == "string_literal"
        end
      end
      nil
    end

    private def ctor_param_type_names(decl : LibTreeSitter::TSNode, source : String) : Array(String)
      result = [] of String
      count = LibTreeSitter.ts_node_named_child_count(decl)
      count.times do |i|
        pc = LibTreeSitter.ts_node_named_child(decl, i.to_u32)
        next unless Noir::TreeSitter.node_type(pc) == "primary_constructor"
        Noir::TreeSitter.each_named_child(pc) do |param|
          next unless Noir::TreeSitter.node_type(param) == "class_parameter"
          Noir::TreeSitter.each_named_child(param) do |c|
            ty = Noir::TreeSitter.node_type(c)
            next unless ty == "user_type" || ty == "nullable_type" || ty == "type_identifier"
            if leaf = type_leaf(c, source)
              result << leaf
              break
            end
          end
        end
      end
      result
    end

    private def simple_type_name(full : String) : String
      if idx = full.rindex('.')
        full[(idx + 1)..]
      else
        full
      end
    end

    # Pull the dotted type name out of a verb call's `<Type>` argument,
    # e.g. `get<Articles.Id.Edit> { }` → "Articles.Id.Edit". Returns nil
    # when the call carries no type argument (the ordinary string-path
    # `get("/x")` form).
    private def call_type_argument_name(call : LibTreeSitter::TSNode, source : String) : String?
      ta = direct_type_arguments(call)
      unless ta
        first = first_named_child(call)
        ta = direct_type_arguments(first) if first && Noir::TreeSitter.node_type(first) == "call_expression"
      end
      return unless ta
      parts = [] of String
      Noir::TreeSitter.each_named_child(ta) do |proj|
        collect_type_identifiers(proj, source, parts, 0)
      end
      parts.empty? ? nil : parts.join(".")
    end

    private def direct_type_arguments(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(node) do |child|
        ty = Noir::TreeSitter.node_type(child)
        return child if ty == "type_arguments"
        if ty == "call_suffix"
          Noir::TreeSitter.each_named_child(child) do |sub|
            return sub if Noir::TreeSitter.node_type(sub) == "type_arguments"
          end
        end
      end
      nil
    end

    private def collect_type_identifiers(node : LibTreeSitter::TSNode, source : String, parts : Array(String), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      parts << Noir::TreeSitter.node_text(node, source) if Noir::TreeSitter.node_type(node) == "type_identifier"
      Noir::TreeSitter.each_named_child(node) do |child|
        collect_type_identifiers(child, source, parts, depth + 1)
      end
    end

    private def resolve_resource_path(type_name : String, resource_paths : Hash(String, String)) : String?
      resource_paths[type_name]? || resource_paths[type_name.split('.').last]?
    end

    # Emit a route for a `verb<Resource> { ... }` call. The path is the
    # composed resource path; the lambda body is scanned for body/query/
    # header params and callees exactly like a string-path verb route.
    private def emit_resource_route(node : LibTreeSitter::TSNode,
                                    source : String,
                                    verb : String,
                                    full_path : String,
                                    routes : Array(Route),
                                    include_callees : Bool)
      line = Noir::TreeSitter.node_start_row(node)
      receive_type : String? = nil
      has_body = false
      query_params = [] of String
      header_params = [] of String
      form_params = [] of String
      callees = [] of Tuple(String, Int32)

      if body = call_lambda_body(node)
        receive_type = scan_handler_body(body, source, query_params, header_params, form_params)
        has_body = !!receive_type || handler_reads_body?(body, source)
        if include_callees
          Noir::KotlinCalleeExtractor.callees_in_lambda(body, source, "").each do |entry|
            name, _path, line_no = entry
            callees << {name, line_no}
          end
        end
      end

      routes << Route.new(verb, full_path, line, receive_type, has_body, query_params, header_params, form_params, callees)
    end

    # ---- traversal ----------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode,
                     source : String,
                     prefix : String,
                     routes : Array(Route),
                     string_constants : Hash(String, String),
                     local_string_constants : Hash(String, String),
                     depth : Int32,
                     include_callees : Bool,
                     active : Bool,
                     resource_paths : Hash(String, String))
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "function_declaration" && route_extension_function?(node, source)
        if body = function_body_statements(node)
          walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true, resource_paths)
        end
        return
      end

      if ty == "call_expression"
        name = call_name(node, source)
        case
        when active && HTTP_VERB_NAMES.has_key?(name)
          type_name = call_type_argument_name(node, source)
          path_arg = call_string_argument(node, source, string_constants, local_string_constants)
          if type_name && path_arg.nil?
            # Type-safe RESOURCE routing: `get<Articles.New> { ... }` —
            # a `<Type>` argument and NO string path. Resolve the type to
            # its @Resource-composed path; if it can't be resolved, skip
            # rather than emit the bare routing prefix (a misleading "/").
            if rp = resolve_resource_path(type_name, resource_paths)
              emit_resource_route(node, source, HTTP_VERB_NAMES[name], join_paths(prefix, rp), routes, include_callees)
            end
            return
          end
          # `post<Body>("/path") { req -> }` (kopapi/typed-body DSL) and the
          # plain `post("/path") { }` form both land here — the `<Type>`,
          # when present alongside a path, names the request body, not a
          # resource. Pass it through as the body type so the param surfaces.
          emit_route(node, source, name, prefix, routes, string_constants, local_string_constants, include_callees, type_name)
          return
        when active && name == "route"
          path_arg = call_string_argument(node, source, string_constants, local_string_constants)
          # Skip `route(unknownArg) { … }` overloads whose sole value
          # argument is neither a string path nor an HTTP method — but let
          # the path-less method form `route(HttpMethod.Get) { handle { } }`
          # (which inherits the enclosing prefix) flow through to the
          # method-route handling below.
          return if path_arg.nil? && call_has_value_arguments?(node) && call_http_method_argument(node, source).nil?
          new_prefix = path_arg ? join_paths(prefix, path_arg) : prefix
          if body = call_lambda_body(node)
            if method = call_http_method_argument(node, source)
              emit_method_route(node, body, source, method, new_prefix, routes, include_callees) if has_handle_call?(body, source)
            end
            walk(body, source, new_prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true, resource_paths)
          end
          return
        when active && name == "resource"
          # `resource<Login> { ... }` is the typed analogue of
          # `route("/path") { ... }`: it pushes the @Resource-composed
          # path of its `<Type>` as the prefix for the nested verb
          # handlers (`post { }`, `method(...) { handle<T> { } }`). When
          # the type resolves, descend with the composed prefix; otherwise
          # fall through to a best-effort walk at the current prefix rather
          # than dropping the whole sub-tree.
          type_name = call_type_argument_name(node, source)
          if type_name && (rp = resolve_resource_path(type_name, resource_paths))
            if body = call_lambda_body(node)
              walk(body, source, join_paths(prefix, rp), routes, string_constants, local_string_constants, depth + 1, include_callees, true, resource_paths)
            end
            return
          end
        when active && name == "method"
          # Path-less verb selector `method(HttpMethod.Get) { handle { } }`
          # that binds the enclosing prefix (typically inside a
          # `resource<T> { }` / `route("/x") { }` block). Without an
          # HttpMethod argument it isn't a route selector — fall through.
          if (method = call_http_method_argument(node, source)) && (body = call_lambda_body(node))
            emit_method_route(node, body, source, method, prefix, routes, include_callees) if has_handle_call?(body, source)
            walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true, resource_paths)
            return
          end
        when active && (name == "staticResources" || name == "staticFiles")
          # `staticResources("/assets", "files")` / `staticFiles("/r", dir)`
          # mount a static directory at a URL prefix — surface that prefix
          # as a GET route (the served files aren't enumerable from
          # source). The remote path is the first string argument.
          if path = static_mount_path(node, source)
            routes << Route.new("GET", join_paths(prefix, path), Noir::TreeSitter.node_start_row(node), nil, false, [] of String, [] of String, [] of String, [] of Tuple(String, Int32))
          end
          return
        when name == "install"
          # `install(Routing) { ... }` contributes routes, so descend as
          # routing. Every other plugin config block (CachingHeaders,
          # CORS, StatusPages, …) is configuration, not routing — descend
          # with routing disabled so a config-DSL lambda that happens to
          # be named like a verb (e.g. CachingHeaders' `options { }`)
          # isn't mistaken for an OPTIONS route.
          if body = call_lambda_body(node)
            walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, routing_install_call?(node, source), resource_paths)
          end
          return
        when name == "routing" || routing_install_call?(node, source) || (active && PASSTHROUGH_NAMES.includes?(name))
          if body = call_lambda_body(node)
            walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true, resource_paths)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, active, resource_paths)
      end
    end

    private def emit_route(node : LibTreeSitter::TSNode,
                           source : String,
                           name : String,
                           prefix : String,
                           routes : Array(Route),
                           string_constants : Hash(String, String),
                           local_string_constants : Hash(String, String),
                           include_callees : Bool,
                           body_type : String? = nil)
      path_arg = call_string_argument(node, source, string_constants, local_string_constants)
      return if path_arg.nil? && call_has_value_arguments?(node) && body_type.nil?
      return unless path_arg || call_has_lambda?(node)

      verb = HTTP_VERB_NAMES[name]
      full_path = join_paths(prefix, path_arg || "")
      line = Noir::TreeSitter.node_start_row(node)

      # A `post<Body>("/x")` typed-body verb names the request body in its
      # type argument; seed it so the json body param surfaces even when
      # the handler never calls `call.receive<T>()` explicitly.
      receive_type : String? = body_type
      has_body = !body_type.nil?
      query_params = [] of String
      header_params = [] of String
      form_params = [] of String
      callees = [] of Tuple(String, Int32)

      if body = call_lambda_body(node)
        scan_handler_body(body, source, query_params, header_params, form_params).tap do |rt|
          receive_type = rt unless rt.nil?
        end
        has_body = has_body || !!receive_type || handler_reads_body?(body, source)
        # KotlinCalleeExtractor uses `(name, file_path, line)` so it can
        # mirror the Java/Python/Go shape, but Ktor's route extractor
        # doesn't carry the file path — drop the placeholder here and
        # let the analyzer attach the real path when it builds the
        # endpoint.
        if include_callees
          Noir::KotlinCalleeExtractor.callees_in_lambda(body, source, "").each do |entry|
            name, _path, line_no = entry
            callees << {name, line_no}
          end
        end
      end

      routes << Route.new(verb, full_path, line, receive_type, has_body, query_params, header_params, form_params, callees)
    end

    private def emit_method_route(node : LibTreeSitter::TSNode,
                                  body : LibTreeSitter::TSNode,
                                  source : String,
                                  verb : String,
                                  full_path : String,
                                  routes : Array(Route),
                                  include_callees : Bool)
      line = Noir::TreeSitter.node_start_row(node)
      query_params = [] of String
      header_params = [] of String
      form_params = [] of String
      receive_type = scan_handler_body(body, source, query_params, header_params, form_params)
      has_body = !!receive_type || handler_reads_body?(body, source)

      callees = [] of Tuple(String, Int32)
      if include_callees
        Noir::KotlinCalleeExtractor.callees_in_lambda(body, source, "").each do |entry|
          name, _path, line_no = entry
          callees << {name, line_no}
        end
      end

      routes << Route.new(verb, full_path, line, receive_type, has_body, query_params, header_params, form_params, callees)
    end

    # ---- call shape helpers ------------------------------------------

    # Read the function name from a `call_expression`. Two shapes:
    #
    # 1. `foo("/x") { ... }` — outer call wraps an inner call_expression
    #    whose first child is a `simple_identifier`.
    # 2. `foo { ... }` — outer call has a `simple_identifier` directly.
    #
    # Anything else (member calls like `call.respond(...)`) returns "".
    private def call_name(call : LibTreeSitter::TSNode, source : String) : String
      first = first_named_child(call)
      return "" unless first

      case Noir::TreeSitter.node_type(first)
      when "simple_identifier"
        Noir::TreeSitter.node_text(first, source)
      when "call_expression"
        inner = first_named_child(first)
        return "" unless inner
        if Noir::TreeSitter.node_type(inner) == "simple_identifier"
          Noir::TreeSitter.node_text(inner, source)
        else
          ""
        end
      when "navigation_expression"
        last_navigation_segment(first, source)
      else
        ""
      end
    end

    # Pull the first `string_literal` argument, if any, from the inner
    # call. Used for `get("/x")` and `route("/api")`.
    private def call_string_argument(call : LibTreeSitter::TSNode,
                                     source : String,
                                     string_constants : Hash(String, String),
                                     local_string_constants : Hash(String, String)) : String?
      first = first_named_child(call)
      return unless first
      return unless Noir::TreeSitter.node_type(first) == "call_expression"

      args = nil
      Noir::TreeSitter.each_named_child(first) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          args = sub if Noir::TreeSitter.node_type(sub) == "value_arguments"
        end
      end
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          if value = resolve_string_value(child, source, string_constants, local_string_constants)
            return value
          end
        end
      end
      nil
    end

    private def call_http_method_argument(call : LibTreeSitter::TSNode, source : String) : String?
      first = first_named_child(call)
      return unless first
      return unless Noir::TreeSitter.node_type(first) == "call_expression"

      args = nil
      Noir::TreeSitter.each_named_child(first) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          args = sub if Noir::TreeSitter.node_type(sub) == "value_arguments"
        end
      end
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          if verb = http_method_value(child, source)
            return verb
          end
        end
      end
      nil
    end

    private def http_method_value(node : LibTreeSitter::TSNode, source : String) : String?
      candidate =
        case Noir::TreeSitter.node_type(node)
        when "simple_identifier"
          Noir::TreeSitter.node_text(node, source)
        when "navigation_expression"
          last_navigation_segment(node, source)
        else
          ""
        end

      return if candidate.empty?
      upcased = candidate.upcase
      HTTP_VERB_NAMES.values.includes?(upcased) ? upcased : nil
    end

    private def routing_install_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      return false unless call_name(call, source) == "install"

      first = first_named_child(call)
      return false unless first
      return false unless Noir::TreeSitter.node_type(first) == "call_expression"

      args = nil
      Noir::TreeSitter.each_named_child(first) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          args = sub if Noir::TreeSitter.node_type(sub) == "value_arguments"
        end
      end
      return false unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          case Noir::TreeSitter.node_type(child)
          when "simple_identifier"
            name = Noir::TreeSitter.node_text(child, source)
            return true if name == "Routing" || name == "RoutingRoot"
          when "navigation_expression"
            text = Noir::TreeSitter.node_text(child, source)
            name = last_navigation_segment(child, source)
            return true if name == "Routing" || name == "RoutingRoot" || text.ends_with?("Routing.Plugin")
          end
        end
      end
      false
    end

    # Locate the lambda body (`statements` node) of a call_expression's
    # trailing lambda — `foo(...) { body }` or `foo { body }`.
    private def call_lambda_body(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          case Noir::TreeSitter.node_type(sub)
          when "annotated_lambda"
            Noir::TreeSitter.each_named_child(sub) do |lam|
              if Noir::TreeSitter.node_type(lam) == "lambda_literal"
                return lambda_statements(lam)
              end
            end
          when "lambda_literal"
            return lambda_statements(sub)
          end
        end
      end
      nil
    end

    private def call_has_lambda?(call : LibTreeSitter::TSNode) : Bool
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          return true if Noir::TreeSitter.node_type(sub) == "annotated_lambda"
          return true if Noir::TreeSitter.node_type(sub) == "lambda_literal"
        end
      end
      false
    end

    private def call_has_value_arguments?(call : LibTreeSitter::TSNode) : Bool
      if call_node_has_value_arguments?(call)
        return true
      end

      first = first_named_child(call)
      if first && Noir::TreeSitter.node_type(first) == "call_expression"
        return true if call_node_has_value_arguments?(first)
      end

      false
    end

    private def call_node_has_value_arguments?(call : LibTreeSitter::TSNode) : Bool
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          next unless Noir::TreeSitter.node_type(sub) == "value_arguments"
          Noir::TreeSitter.each_named_child(sub) do |arg|
            return true if Noir::TreeSitter.node_type(arg) == "value_argument"
          end
        end
      end
      false
    end

    private def has_handle_call?(node : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : Bool
      return false if depth > Noir::TreeSitter::MAX_AST_DEPTH
      if Noir::TreeSitter.node_type(node) == "call_expression" && call_name(node, source) == "handle"
        return true
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        return true if has_handle_call?(child, source, depth + 1)
      end
      false
    end

    private def route_extension_function?(func : LibTreeSitter::TSNode, source : String) : Bool
      receiver = nil
      Noir::TreeSitter.each_named_child(func) do |child|
        if Noir::TreeSitter.node_type(child) == "user_type"
          receiver = child
          break
        end
      end
      return false unless receiver

      last_type = ""
      Noir::TreeSitter.each_named_child(receiver) do |child|
        if Noir::TreeSitter.node_type(child) == "type_identifier"
          last_type = Noir::TreeSitter.node_text(child, source)
        end
      end
      last_type == "Route" || last_type == "Routing"
    end

    private def function_body_statements(func : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(func) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_body"
        Noir::TreeSitter.each_named_child(child) do |sub|
          return sub if Noir::TreeSitter.node_type(sub) == "statements"
        end
      end
      nil
    end

    private def lambda_statements(lambda_lit : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(lambda_lit) do |child|
        return child if Noir::TreeSitter.node_type(child) == "statements"
      end
      nil
    end

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      # Walk the string's children. A plain string has one
      # `string_content` child; a Kotlin template string interleaves
      # `string_content` with `interpolated_identifier` ("$var",
      # short form) and `interpolated_expression` ("${expr}", long
      # form) nodes. Pre-fix, the interpolation children were dropped
      # entirely, so `"/api/$VERSION/items"` collapsed to
      # `/api//items` (and the optimizer normalized the double-
      # slash to `/api/items`) — the user's URL silently lost the
      # path segment, just like the Python f-string bug.
      #
      # Wrap the interpolated identifier/expression in `{…}` so the
      # placeholder is preserved and the downstream path-param
      # extractor picks it up.
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          when "interpolated_identifier", "interpolated_expression"
            # node_text for these children is the identifier / inner
            # expression with the leading `$` (and `{…}` for the
            # expression form) already stripped by the grammar.
            io << '{'
            io << Noir::TreeSitter.node_text(child, source).strip
            io << '}'
          end
        end
      end
      buf
    end

    # ---- handler-body scan -------------------------------------------

    # Recurse through the lambda body collecting body params. We
    # short-circuit on nested verb DSL calls — those are routes in
    # their own right and `walk` will hit them as separate nodes (we
    # never invoke `scan_handler_body` from `walk`'s recursion path,
    # only when emitting a route).
    private def scan_handler_body(node : LibTreeSitter::TSNode,
                                  source : String,
                                  query_params : Array(String),
                                  header_params : Array(String),
                                  form_params : Array(String)) : String?
      receive_type : String? = nil
      form_vars = Set(String).new
      walk_handler(node, source, query_params, header_params, form_params, form_vars, 0) do |type|
        receive_type ||= type
      end
      receive_type
    end

    private def walk_handler(node : LibTreeSitter::TSNode,
                             source : String,
                             query_params : Array(String),
                             header_params : Array(String),
                             form_params : Array(String),
                             form_vars : Set(String),
                             depth : Int32,
                             &block : String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      case ty
      when "property_declaration"
        if receive_parameters_assignment?(node, source)
          if name = property_name(node, source)
            form_vars << name
          end
        end
      when "call_expression"
        if call_is_call_receive?(node, source)
          if type_arg = call_receive_type_argument(node, source)
            block.call(type_arg)
          end
          return
        elsif call_reads_request_body?(node, source)
          block.call("")
          return
        elsif name = call_string_parameter(node, source)
          first = first_named_child(node)
          if first
            chain = navigation_chain(first, source)
            if chain == ["call", "parameters", "get"] || chain == ["call", "request", "queryParameters", "get"]
              query_params << name
            elsif chain == ["call", "request", "headers", "get"] || chain == ["call", "request", "header"]
              header_params << name
            elsif chain.size == 2 && form_vars.includes?(chain.first) && chain.last == "get"
              form_params << name
            end
          end
        end
      when "indexing_expression"
        target = first_named_child(node)
        if target
          chain = navigation_chain(target, source)
          if chain == ["call", "parameters"]
            if name = indexing_string_key(node, source)
              query_params << name
            end
          elsif chain == ["call", "request", "queryParameters"]
            if name = indexing_string_key(node, source)
              query_params << name
            end
          elsif chain == ["call", "request", "headers"]
            if name = indexing_string_key(node, source)
              header_params << name
            end
          elsif chain.size == 1 && form_vars.includes?(chain.first)
            if name = indexing_string_key(node, source)
              form_params << name
            end
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_handler(child, source, query_params, header_params, form_params, form_vars, depth + 1, &block)
      end
    end

    private def call_is_call_receive?(call : LibTreeSitter::TSNode, source : String) : Bool
      first = first_named_child(call)
      return false unless first
      return false unless Noir::TreeSitter.node_type(first) == "navigation_expression"
      chain = navigation_chain(first, source)
      chain == ["call", "receive"] || chain == ["call", "receiveNullable"]
    end

    private def call_reads_request_body?(call : LibTreeSitter::TSNode, source : String) : Bool
      first = first_named_child(call)
      return false unless first
      return false unless Noir::TreeSitter.node_type(first) == "navigation_expression"
      chain = navigation_chain(first, source)
      chain == ["call", "receiveText"] || chain == ["call", "receiveChannel"] || chain == ["call", "receiveStream"]
    end

    private def handler_reads_body?(node : LibTreeSitter::TSNode, source : String) : Bool
      body_reader?(node, source, 0)
    end

    private def body_reader?(node : LibTreeSitter::TSNode, source : String, depth : Int32) : Bool
      return false if depth > Noir::TreeSitter::MAX_AST_DEPTH
      if Noir::TreeSitter.node_type(node) == "call_expression"
        if call_is_call_receive?(node, source) || call_reads_request_body?(node, source)
          return true
        end
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        return true if body_reader?(child, source, depth + 1)
      end
      false
    end

    private def receive_parameters_assignment?(node : LibTreeSitter::TSNode, source : String) : Bool
      Noir::TreeSitter.each_named_child(node) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_expression"
        first = first_named_child(child)
        next unless first
        next unless Noir::TreeSitter.node_type(first) == "navigation_expression"
        return true if navigation_chain(first, source) == ["call", "receiveParameters"]
      end
      false
    end

    private def property_name(node : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(node) do |child|
        next unless Noir::TreeSitter.node_type(child) == "variable_declaration"
        Noir::TreeSitter.each_named_child(child) do |sub|
          return Noir::TreeSitter.node_text(sub, source) if Noir::TreeSitter.node_type(sub) == "simple_identifier"
        end
      end
      nil
    end

    private def call_string_parameter(call : LibTreeSitter::TSNode, source : String) : String?
      first = first_named_child(call)
      return unless first
      return unless Noir::TreeSitter.node_type(first) == "navigation_expression"
      first_string_argument(call, source)
    end

    # Pull the `<T>` from `call.receive<T>()`. The `call_suffix` of
    # the call_expression carries a `type_arguments` child whose
    # `type_projection` wraps a `user_type` (or nullable wrapper).
    private def call_receive_type_argument(call : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          next unless Noir::TreeSitter.node_type(sub) == "type_arguments"
          Noir::TreeSitter.each_named_child(sub) do |proj|
            next unless Noir::TreeSitter.node_type(proj) == "type_projection"
            return type_leaf(proj, source)
          end
        end
      end
      nil
    end

    # Walk down a `type_projection` / `user_type` / `nullable_type`
    # chain to its `type_identifier` leaf. The depth bound here is
    # defence-in-depth — Kotlin types nesting beyond a few dozen
    # levels would already break the grammar, but the same recursion
    # discipline as the route walker keeps the surface uniform.
    private def type_leaf(node : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : String?
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      ty = Noir::TreeSitter.node_type(node)
      return Noir::TreeSitter.node_text(node, source) if ty == "type_identifier"

      Noir::TreeSitter.each_named_child(node) do |child|
        if leaf = type_leaf(child, source, depth + 1)
          return leaf
        end
      end
      nil
    end

    # Collapse `a.b.c` (a chain of `navigation_expression` /
    # `simple_identifier` / `navigation_suffix` nodes) into the
    # `["a", "b", "c"]` identifier list. Returns an empty array when
    # the expression has any non-identifier components.
    private def navigation_chain(node : LibTreeSitter::TSNode, source : String) : Array(String)
      chain = [] of String
      collect_chain(node, source, chain)
      chain
    end

    private def collect_chain(node : LibTreeSitter::TSNode, source : String, chain : Array(String))
      ty = Noir::TreeSitter.node_type(node)
      case ty
      when "simple_identifier"
        chain << Noir::TreeSitter.node_text(node, source)
      when "navigation_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "navigation_expression", "simple_identifier"
            collect_chain(child, source, chain)
          when "navigation_suffix"
            Noir::TreeSitter.each_named_child(child) do |sub|
              collect_chain(sub, source, chain) if Noir::TreeSitter.node_type(sub) == "simple_identifier"
            end
          else
            chain << "" # poison the chain — caller's `==` compare fails
          end
        end
      else
        chain << ""
      end
    end

    private def last_navigation_segment(node : LibTreeSitter::TSNode, source : String) : String
      result = ""
      Noir::TreeSitter.each_named_child(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "simple_identifier"
          result = Noir::TreeSitter.node_text(child, source)
        when "navigation_suffix"
          Noir::TreeSitter.each_named_child(child) do |sub|
            if Noir::TreeSitter.node_type(sub) == "simple_identifier"
              result = Noir::TreeSitter.node_text(sub, source)
            end
          end
        end
      end
      result
    end

    # `["x"]` → `"x"`. Anything else (interpolated string, identifier
    # key) returns nil so the caller skips emitting a param.
    private def indexing_string_key(idx : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(idx) do |child|
        next unless Noir::TreeSitter.node_type(child) == "indexing_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          if Noir::TreeSitter.node_type(sub) == "string_literal"
            return decode_string_literal(sub, source)
          end
        end
      end
      nil
    end

    private def first_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          next unless Noir::TreeSitter.node_type(sub) == "value_arguments"
          Noir::TreeSitter.each_named_child(sub) do |arg|
            next unless Noir::TreeSitter.node_type(arg) == "value_argument"
            Noir::TreeSitter.each_named_child(arg) do |value|
              return decode_string_literal(value, source) if Noir::TreeSitter.node_type(value) == "string_literal"
            end
          end
        end
      end
      nil
    end

    # First string argument of a static-content call, whether or not it
    # carries a trailing config lambda. `staticResources("/r", "dir")`
    # keeps the args on the call's own `call_suffix`; the braced form
    # `staticResources("/", "dir") { ... }` parses the args onto an inner
    # `call_expression` instead, so check both.
    private def static_mount_path(call : LibTreeSitter::TSNode, source : String) : String?
      if value = first_string_argument(call, source)
        return value
      end
      first = first_named_child(call)
      if first && Noir::TreeSitter.node_type(first) == "call_expression"
        return first_string_argument(first, source)
      end
      nil
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     string_constants : Hash(String, String),
                                     local_string_constants : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "simple_identifier"
        local_string_constants[Noir::TreeSitter.node_text(node, source)]?
      when "navigation_expression"
        text = Noir::TreeSitter.node_text(node, source)
        local_string_constants[text]? || string_constants[text]?
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          return resolve_string_value(child, source, string_constants, local_string_constants)
        end
      when "additive_expression"
        parts = [] of String
        Noir::TreeSitter.each_named_child(node) do |child|
          part = resolve_string_value(child, source, string_constants, local_string_constants)
          return unless part
          parts << part
        end
        parts.join
      end
    end

    private def join_paths(prefix : String, suffix : String) : String
      return "/" if prefix.empty? && suffix.empty?
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
