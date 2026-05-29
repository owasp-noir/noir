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
  #   * Inside each verb's lambda body:
  #     - `call.receive<T>()` → `body` parameter typed `T` as `json`
  #     - `call.parameters["name"]` → `name` parameter as `query`
  #     - `call.request.headers["name"]` → `name` parameter as `header`
  #
  # Not covered yet (out of scope for this first cut):
  #
  #   * Resource-based routing (`get<Resource> { ... }`).
  #   * Type-safe routing via `@Resource`.
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
    }

    # Pass-through DSL calls — descend into their lambda body without
    # changing the path prefix. `routing` is the entry point;
    # `authenticate` wraps a sub-tree behind an auth realm; the
    # remaining names cover the common Ktor scoping helpers.
    PASSTHROUGH_NAMES = Set{
      "routing",
      "authenticate",
      "rateLimit",
      "install",
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

    def extract_routes(source : String, string_constants = Hash(String, String).new, *, include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      local_string_constants = extract_string_constants(source)
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk(root, source, "", routes, string_constants, local_string_constants, 0, include_callees, false)
      end
      routes
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
          current_depth += line.count("{")
          current_depth -= line.count("}")
          if current_depth <= 0 && line.includes?("}")
            current_type = ""
            current_depth = 0
          end
        end
      end

      constants
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
                     active : Bool)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "function_declaration" && route_extension_function?(node, source)
        if body = function_body_statements(node)
          walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true)
        end
        return
      end

      if ty == "call_expression"
        name = call_name(node, source)
        case
        when active && HTTP_VERB_NAMES.has_key?(name)
          emit_route(node, source, name, prefix, routes, string_constants, local_string_constants, include_callees)
          return
        when active && name == "route"
          path_arg = call_string_argument(node, source, string_constants, local_string_constants)
          return if path_arg.nil? && call_has_value_arguments?(node)
          new_prefix = path_arg ? join_paths(prefix, path_arg) : prefix
          if body = call_lambda_body(node)
            if method = call_http_method_argument(node, source)
              emit_method_route(node, body, source, method, new_prefix, routes, include_callees) if has_handle_call?(body, source)
            end
            walk(body, source, new_prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true)
          end
          return
        when name == "routing" || routing_install_call?(node, source) || (active && PASSTHROUGH_NAMES.includes?(name))
          if body = call_lambda_body(node)
            walk(body, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, active)
      end
    end

    private def emit_route(node : LibTreeSitter::TSNode,
                           source : String,
                           name : String,
                           prefix : String,
                           routes : Array(Route),
                           string_constants : Hash(String, String),
                           local_string_constants : Hash(String, String),
                           include_callees : Bool)
      path_arg = call_string_argument(node, source, string_constants, local_string_constants)
      return if path_arg.nil? && call_has_value_arguments?(node)
      return unless path_arg || call_has_lambda?(node)

      verb = HTTP_VERB_NAMES[name]
      full_path = join_paths(prefix, path_arg || "")
      line = Noir::TreeSitter.node_start_row(node)

      receive_type : String? = nil
      has_body = false
      query_params = [] of String
      header_params = [] of String
      form_params = [] of String
      callees = [] of Tuple(String, Int32)

      if body = call_lambda_body(node)
        scan_handler_body(body, source, query_params, header_params, form_params).tap do |rt|
          receive_type = rt
        end
        has_body = !!receive_type || handler_reads_body?(body, source)
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
