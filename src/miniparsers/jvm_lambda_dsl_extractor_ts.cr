require "../ext/tree_sitter/tree_sitter"
require "./java_callee_extractor"
require "./java_route_extractor_ts"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed walker for JVM "lambda DSL" routing styles —
  # `verb("/path", lambda)` plus optional `path("/prefix", () -> {
  # ... })` nesting. Same shape powers Javalin (`app.get("/x", ctx
  # -> ...)`), Spark Java (`get("/x", (req, res) -> ...)`), and
  # other Sinatra-flavoured Java frameworks.
  #
  # The walker is configured per framework:
  #
  #   * `verb_methods`   — method names mapped to HTTP verbs.
  #   * `websocket_methods` — method names that declare WebSocket
  #                           endpoints. These are surfaced as GET
  #                           routes with `protocol = "ws"`.
  #   * `crud_methods`   — method names that expand a resource path
  #                        into GET collection, POST collection, GET
  #                        item, PATCH item, and DELETE item routes.
  #   * `nest_methods`   — method names that introduce a path
  #                        prefix (typically `path` and any
  #                        equivalent grouping helper).
  #   * `transparent_methods` — method names whose lambda body
  #                             contributes routes without changing
  #                             the prefix (Javalin's `routes`).
  #   * `query_methods` / `form_methods` / `header_methods` /
  #     `cookie_methods` — lambda-body method calls that yield an
  #     input parameter. Each takes the param name from a string
  #     argument or, when absent, falls back to surfacing the call's
  #     receiver name. Method names alone identify a category — we
  #     don't enforce a specific receiver, so framework-overlap
  #     mistakes show up as cross-framework noise rather than as
  #     missed signals.
  #   * `body_methods`   — calls that signal a request body without
  #                        a type clue (Spark's `req.body()`).
  #   * `body_typed_methods` — calls that take a class-literal
  #                            argument indicating the body type
  #                            (Javalin's `ctx.bodyAsClass(Foo.class)`).
  #
  # Out of scope for this first cut: filter chains, reverse routing,
  # cross-file route registration. Routes scoped under static factory
  # methods are still discovered as long as their lambda body lives
  # in the same file.
  module TreeSitterJvmLambdaDslExtractor
    extend self

    struct Config
      getter verb_methods : Hash(String, String)
      getter websocket_methods : Set(String)
      getter handler_methods : Set(String)
      getter crud_methods : Set(String)
      getter nest_methods : Set(String)
      getter transparent_methods : Set(String)
      getter query_methods : Set(String)
      getter form_methods : Set(String)
      getter header_methods : Set(String)
      getter cookie_methods : Set(String)
      getter body_methods : Set(String)
      getter body_typed_methods : Set(String)
      # Receiver names (the `object` in `recv.get(...)`) that mark a
      # verb call as a genuine route registration even when it carries
      # no functional handler argument. Spark's redirect API
      # (`redirect.get("/from", "/to")`) is the canonical case — its
      # arguments are all string literals, so without an explicit
      # allowlist it's indistinguishable from a colliding collection
      # call like `map.put("k", "v")`. Matched against the receiver's
      # last dotted segment, so both `redirect.get(...)` and
      # `Spark.redirect.get(...)` resolve to `redirect`.
      getter router_receivers : Set(String)

      def initialize(@verb_methods,
                     @nest_methods,
                     @handler_methods = Set(String).new,
                     @crud_methods = Set(String).new,
                     @transparent_methods = Set(String).new,
                     @query_methods = Set(String).new,
                     @form_methods = Set(String).new,
                     @header_methods = Set(String).new,
                     @cookie_methods = Set(String).new,
                     @body_methods = Set(String).new,
                     @body_typed_methods = Set(String).new,
                     @websocket_methods = Set(String).new,
                     @router_receivers = Set(String).new)
      end
    end

    struct Route
      getter verb : String
      getter path : String
      getter protocol : String
      getter line : Int32
      getter body_type : String?
      getter? has_body : Bool
      getter query_params : Array(String)
      getter form_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)
      # 1-hop callees out of the handler lambda body. `path` is filled
      # in by the analyzer (the route extractor doesn't carry the file
      # path itself); each tuple is (callee_name, line_1_based).
      getter callees : Array(Tuple(String, Int32))

      def initialize(@verb, @path, @line, @body_type, @has_body,
                     @query_params, @form_params, @header_params, @cookie_params,
                     @callees, @protocol = "http")
      end
    end

    def extract_routes(source : String, config : Config, *, include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
        method_bodies = method_body_index(root, source)
        walk(root, source, "", config, routes, constants, method_bodies, 0, include_callees)
      end
      routes
    end

    # ---- traversal ---------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode,
                     source : String,
                     prefix : String,
                     config : Config,
                     routes : Array(Route),
                     constants : Hash(String, String),
                     method_bodies : Hash(String, LibTreeSitter::TSNode),
                     depth : Int32,
                     include_callees : Bool)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "method_invocation"
        name = method_invocation_method_name(node, source)
        case
        when verb = config.verb_methods[name]?
          emit_route(node, source, verb, prefix, config, routes, constants, method_bodies, include_callees)
          return
        when config.websocket_methods.includes?(name)
          emit_route(node, source, "GET", prefix, config, routes, constants, method_bodies, include_callees, protocol: "ws")
          return
        when config.handler_methods.includes?(name)
          emit_handler_route(node, source, prefix, config, routes, constants, method_bodies, include_callees)
          return
        when config.crud_methods.includes?(name)
          emit_crud_routes(node, source, prefix, routes, constants)
          return
        when config.nest_methods.includes?(name)
          path_arg = first_string_argument(node, source, constants)
          new_prefix = path_arg ? join_paths(prefix, path_arg) : prefix
          if body = lambda_body_in_args(node)
            walk(body, source, new_prefix, config, routes, constants, method_bodies, depth + 1, include_callees)
          end
          return
        when config.transparent_methods.includes?(name)
          if body = lambda_body_in_args(node)
            walk(body, source, prefix, config, routes, constants, method_bodies, depth + 1, include_callees)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, config, routes, constants, method_bodies, depth + 1, include_callees)
      end
    end

    private def emit_route(call : LibTreeSitter::TSNode,
                           source : String,
                           verb : String,
                           prefix : String,
                           config : Config,
                           routes : Array(Route),
                           constants : Hash(String, String),
                           method_bodies : Hash(String, LibTreeSitter::TSNode),
                           include_callees : Bool,
                           protocol : String = "http")
      return unless route_invocation?(call, source, config)

      path_arg = first_string_argument(call, source, constants)
      if path_arg.nil?
        return if prefix.empty? || !pathless_handler_argument?(call)
        path_arg = ""
      end

      full_path = join_paths(prefix, path_arg)
      line = Noir::TreeSitter.node_start_row(call)

      query_params = [] of String
      form_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      body_type : String? = nil
      has_body = false
      callees = [] of Tuple(String, Int32)

      body = lambda_body_in_args(call) || method_reference_body_in_args(call, source, method_bodies)
      if body
        scan_handler(body, source, config, constants, 0) do |kind, value|
          case kind
          when :query  then query_params << value
          when :form   then form_params << value
          when :header then header_params << value
          when :cookie then cookie_params << value
          when :body   then has_body = true
          when :body_typed
            body_type = value
            has_body = true
          end
        end
        # JavaCalleeExtractor takes (name, file_path, line); the route
        # extractor doesn't carry the file path, so drop the placeholder
        # here and let the analyzer attach the real path when it builds
        # the endpoint.
        if include_callees
          Noir::JavaCalleeExtractor.callees_in_lambda(body, source, "").each do |entry|
            name, _path, line_no = entry
            callees << {name, line_no}
          end
        end
      end

      routes << Route.new(verb, full_path, line, body_type, has_body,
        query_params, form_params, header_params, cookie_params, callees, protocol)
    end

    private def emit_handler_route(call : LibTreeSitter::TSNode,
                                   source : String,
                                   prefix : String,
                                   config : Config,
                                   routes : Array(Route),
                                   constants : Hash(String, String),
                                   method_bodies : Hash(String, LibTreeSitter::TSNode),
                                   include_callees : Bool)
      verb = first_http_method_argument(call, source)
      return unless verb

      emit_route(call, source, verb, prefix, config, routes, constants, method_bodies, include_callees)
    end

    private def emit_crud_routes(call : LibTreeSitter::TSNode,
                                 source : String,
                                 prefix : String,
                                 routes : Array(Route),
                                 constants : Hash(String, String))
      item_path_arg = first_string_argument(call, source, constants)
      return if item_path_arg.nil? && prefix.empty?

      item_path = item_path_arg ? join_paths(prefix, item_path_arg) : prefix
      collection_path = crud_collection_path(item_path)
      line = Noir::TreeSitter.node_start_row(call)

      [
        {"GET", collection_path},
        {"POST", collection_path},
        {"GET", item_path},
        {"PATCH", item_path},
        {"DELETE", item_path},
      ].each do |entry|
        verb, path = entry
        routes << Route.new(verb, path, line, nil, false,
          [] of String, [] of String, [] of String, [] of String,
          [] of Tuple(String, Int32))
      end
    end

    private def scan_handler(node : LibTreeSitter::TSNode,
                             source : String,
                             config : Config,
                             constants : Hash(String, String),
                             depth : Int32,
                             &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "method_invocation"
        name = method_invocation_method_name(node, source)

        # Don't recurse into nested verb calls — those are sibling
        # routes in their own right and the outer `walk` will reach
        # them.
        return if config.verb_methods.has_key?(name) && route_like_invocation?(node, source, constants)
        return if config.websocket_methods.includes?(name)
        return if config.handler_methods.includes?(name)
        return if config.nest_methods.includes?(name)

        case
        when config.query_methods.includes?(name)
          if value = first_string_argument(node, source, constants)
            block.call(:query, value)
          end
        when config.form_methods.includes?(name)
          if value = first_string_argument(node, source, constants)
            block.call(:form, value)
          end
        when config.header_methods.includes?(name)
          if value = first_string_argument(node, source, constants)
            block.call(:header, value)
          end
        when config.cookie_methods.includes?(name)
          if value = first_string_argument(node, source, constants)
            block.call(:cookie, value)
          end
        when config.body_typed_methods.includes?(name)
          type = first_class_literal_type(node, source)
          block.call(:body_typed, type || "")
        when config.body_methods.includes?(name)
          block.call(:body, "")
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, config, constants, depth + 1, &block)
      end
    end

    # ---- shape helpers ----------------------------------------------

    # `app.get("/x", ...)` and `Spark.get("/x", ...)` both produce
    # a `method_invocation` whose last `identifier` child before the
    # `argument_list` is the method name. Static unqualified calls
    # (`get("/x", ...)` after a static import) only have a single
    # `identifier` child preceding the `argument_list`.
    private def method_invocation_method_name(call : LibTreeSitter::TSNode, source : String) : String
      if name_node = Noir::TreeSitter.field(call, "name")
        return Noir::TreeSitter.node_text(name_node, source)
      end

      result = ""
      Noir::TreeSitter.each_named_child(call) do |child|
        ty = Noir::TreeSitter.node_type(child)
        case ty
        when "identifier"
          result = Noir::TreeSitter.node_text(child, source)
        when "argument_list"
          break
        end
      end
      result
    end

    private def first_string_argument(call : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String)) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
          if value = resolve_string_value(arg, source, constants)
            return value
          end
        end
      end
      nil
    end

    private def first_http_method_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = argument_list_node(call)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        text = Noir::TreeSitter.node_text(arg, source)
        if match = text.match(/(?:HandlerType|HttpMethod)\.([A-Z]+)/)
          return match[1]
        end
      end

      nil
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     constants : Hash(String, String),
                                     depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier", "field_access", "scoped_identifier"
        resolve_constant_reference(Noir::TreeSitter.node_text(node, source), constants)
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_value = resolve_string_value(left, source, constants, depth + 1)
        right_value = resolve_string_value(right, source, constants, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_string_value(child, source, constants, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String, constants : Hash(String, String)) : String?
      if resolved = constants[name]?
        return resolved
      end

      suffix = ".#{name}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def first_class_literal_type(call : LibTreeSitter::TSNode, source : String) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "class_literal"
        Noir::TreeSitter.each_named_child(arg) do |child|
          if Noir::TreeSitter.node_type(child) == "type_identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      nil
    end

    private def argument_list_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "argument_list"
      end
      nil
    end

    # Pull the lambda's body (`block` or expression) out of the
    # call's argument list. Returns nil if no lambda is passed.
    private def lambda_body_in_args(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "lambda_expression"
        Noir::TreeSitter.each_named_child(arg) do |child|
          ty = Noir::TreeSitter.node_type(child)
          # The lambda parameter list (identifier / formal_parameters /
          # inferred_parameters) precedes the body — skip it.
          next if ty == "identifier" || ty == "formal_parameters" || ty == "inferred_parameters"
          return child
        end
      end
      nil
    end

    private def method_reference_body_in_args(call : LibTreeSitter::TSNode,
                                              source : String,
                                              method_bodies : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      args = argument_list_node(call)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "method_reference"

        method_name = Noir::TreeSitter.node_text(arg, source).split("::").last?.to_s
        method_name = method_name.gsub(/\A<[^>]+>/, "")
        next if method_name.empty?

        if body = method_bodies[method_name]?
          return body
        end
      end

      nil
    end

    private def method_body_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      bodies = Hash(String, LibTreeSitter::TSNode).new

      walk_method_declarations(root) do |method|
        name_node = Noir::TreeSitter.field(method, "name")
        body = Noir::TreeSitter.field(method, "body")
        next unless name_node && body

        name = Noir::TreeSitter.node_text(name_node, source)
        bodies[name] ||= body
      end

      bodies
    end

    private def walk_method_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_method_declarations(child, &block)
      end
    end

    private def pathless_handler_argument?(call : LibTreeSitter::TSNode) : Bool
      args = argument_list_node(call)
      return false unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "lambda_expression", "method_reference"
          return true
        end
      end

      false
    end

    private def route_like_invocation?(call : LibTreeSitter::TSNode,
                                       source : String,
                                       constants : Hash(String, String)) : Bool
      !!first_string_argument(call, source, constants) || pathless_handler_argument?(call)
    end

    # Guard against collisions between verb method names and ordinary
    # collection / builder calls that happen to share them — e.g.
    # `usernamePasswords.put("foo", "bar")` (a `Map.put`) reads exactly
    # like `put("/foo", handler)` once you only look at the method name
    # and a string argument. A call is a genuine route when ANY holds:
    #
    #   * it's unqualified (`get("/x", ...)`) — `import static
    #     spark.Spark.*` style, never a method on a user object;
    #   * it carries a functional handler argument (lambda, method
    #     reference, anonymous class, or class literal) — collection
    #     mutators pass plain values, never handlers;
    #   * its receiver is an allowlisted router (Spark's `redirect`),
    #     which lets the all-string-literal redirect forms through.
    private def route_invocation?(call : LibTreeSitter::TSNode,
                                  source : String,
                                  config : Config) : Bool
      receiver = Noir::TreeSitter.field(call, "object")
      return true unless receiver
      return true if functional_handler_argument?(call)
      config.router_receivers.includes?(receiver_key(receiver, source))
    end

    # Last dotted segment of the receiver expression: `redirect` for
    # both `redirect.get(...)` and `service.redirect.get(...)`.
    private def receiver_key(receiver : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.node_text(receiver, source).split('.').last.strip
    end

    private def functional_handler_argument?(call : LibTreeSitter::TSNode) : Bool
      args = argument_list_node(call)
      return false unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "lambda_expression", "method_reference",
             "object_creation_expression", "class_literal"
          return true
        end
      end

      false
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"') ? raw[1..-2] : raw
    end

    # Single-`/` join: `prefix + suffix` with one separator,
    # collapsing trailing/leading slashes. Empty prefix or suffix is
    # passed through unchanged.
    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    private def crud_collection_path(item_path : String) : String
      trimmed = item_path.rstrip('/')
      return trimmed if trimmed.empty?

      if match = trimmed.match(%r{/\{[^/]+\}\z})
        collection = trimmed[0...match.begin(0)]
        return collection.empty? ? "/" : collection
      end

      trimmed
    end
  end
end
