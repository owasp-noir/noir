require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./kotlin_callee_extractor"

module Noir
  # Tree-sitter-backed http4k extractor.
  #
  # http4k uses Kotlin's infix-call syntax to register routes inside
  # a top-level `routes(...)` call:
  #
  # ```
  # val app = routes(
  #     "/users" bind GET to { req: Request -> ... },
  #     "/users/{id}" bind POST to ::createUser,
  #     "/api" bind routes(
  #         "/status" bind GET to handler,
  #         "/v1" bind routes(
  #             "/health" bind Method.GET to other
  #         )
  #     )
  # )
  # ```
  #
  # `path bind VERB to handler` is parsed as a nested `infix_expression`
  # — the inner `bind` glues path to verb, the outer `to` attaches the
  # handler. `path bind routes(...)` is the prefix-grouping form.
  #
  # Recognised:
  #
  #   * Verbs `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `HEAD`,
  #     `OPTIONS`, `TRACE`, `CONNECT` — both bare (`GET`) and
  #     `Method.GET`-qualified.
  #   * Inline lambda handler — scanned for `req.query("name")`,
  #     `req.header("X-Foo")`, `req.form("x")`, `req.bodyString()`
  #     calls. `req.path("id")` is skipped (the URL placeholder
  #     already carries it; the optimizer synthesises a path Param).
  #   * `path bind routes(...)` — prefix composition with
  #     `single-/` joining.
  #
  # Out of scope for this first cut:
  #
  #   * Lens-based body / form / header (`Body.auto<T>()`,
  #     `Header.required("X")`). These are powerful but require
  #     cross-call value tracking — a follow-up.
  #   * Callable-reference handlers (`::myHandler`) — we emit the
  #     route without scanning the function's body.
  #   * `static` / `singlePageApp` for static asset routes.
  module TreeSitterHttp4kExtractor
    extend self

    HTTP_VERBS = Set{
      "GET", "POST", "PUT", "DELETE", "PATCH",
      "HEAD", "OPTIONS", "TRACE", "CONNECT",
    }

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter? has_body : Bool
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter form_params : Array(String)
      # 1-hop callees out of the handler expression. `path` is filled
      # in by the analyzer (the route extractor doesn't carry the
      # file path); each tuple is (callee_name, line_1_based).
      getter callees : Array(Tuple(String, Int32))

      def initialize(@verb, @path, @line, @has_body,
                     @query_params, @header_params, @form_params,
                     @callees)
      end

      def with_path(path : String) : Route
        Route.new(@verb, path, @line, @has_body, @query_params, @header_params, @form_params, @callees)
      end
    end

    def extract_routes(source : String,
                       string_constants = Hash(String, String).new,
                       *,
                       include_callees : Bool = false,
                       contract_routes = Hash(String, Array(Route)).new) : Array(Route)
      routes = [] of Route
      local_string_constants = extract_string_constants(source)
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk(root, source, "", routes, string_constants, local_string_constants, 0, include_callees, false, contract_routes)
      end
      routes
    end

    def extract_contract_route_functions(source : String,
                                         string_constants = Hash(String, String).new,
                                         *,
                                         include_callees : Bool = false) : Hash(String, Array(Route))
      routes_by_function = Hash(String, Array(Route)).new
      local_string_constants = extract_string_constants(source)
      Noir::TreeSitter.parse_kotlin(source) do |root|
        collect_contract_route_functions(root, source, routes_by_function, string_constants, local_string_constants, include_callees, 0)
      end
      routes_by_function
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

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode,
                     source : String,
                     prefix : String,
                     routes : Array(Route),
                     string_constants : Hash(String, String),
                     local_string_constants : Hash(String, String),
                     depth : Int32,
                     include_callees : Bool,
                     in_routes : Bool,
                     contract_routes : Hash(String, Array(Route)))
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "infix_expression" && handle_bind(node, source, prefix, routes, string_constants, local_string_constants, depth, include_callees, in_routes, contract_routes)
        return
      end

      if ty == "call_expression" && call_function_name(node, source) == "routes"
        # Arguments of a `routes(...)` call are inside the routing
        # block — a bare `VERB to handler` arg there is a real route
        # bound to the current prefix (the verbs-under-path idiom).
        walk_routes_args(node, source, prefix, routes, string_constants, local_string_constants, depth, include_callees, true, contract_routes)
        return
      end

      if ty == "call_expression" && call_function_name(node, source) == "contract"
        emit_contract_routes(node, source, prefix, routes, contract_routes)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, in_routes, contract_routes)
      end
    end

    # Try to interpret an `infix_expression` as one of:
    #
    #   - `path bind VERB to handler` — emit a route.
    #   - `path bind routes(...)`     — prefix composition; recurse.
    #
    # Returns true when consumed; false otherwise so the caller can
    # fall through to the generic descent.
    private def handle_bind(node : LibTreeSitter::TSNode,
                            source : String,
                            prefix : String,
                            routes : Array(Route),
                            string_constants : Hash(String, String),
                            local_string_constants : Hash(String, String),
                            depth : Int32,
                            include_callees : Bool,
                            in_routes : Bool,
                            contract_routes : Hash(String, Array(Route))) : Bool
      lhs, op, rhs = infix_parts(node, source)
      return false unless lhs && rhs

      case op
      when "to"
        if Noir::TreeSitter.node_type(lhs) == "infix_expression"
          # `path bind VERB to handler` — the canonical form — or
          # `path[ meta {...}] bindContract VERB to handler` for the
          # contract DSL. Both glue a literal path to a verb on the
          # inner infix, then attach the handler via the outer `to`.
          inner_lhs, inner_op, inner_rhs = infix_parts(lhs, source)
          return false unless inner_op == "bind" || inner_op == "bindContract"
          return false unless inner_lhs && inner_rhs

          # `bindContract` routes are almost always defined in a helper
          # function returning `ContractRoute` and assembled into a
          # `contract { routes += foo() }` block mounted under a prefix
          # elsewhere — so emitting them standalone yields a path that's
          # missing its mount prefix (a wrong URL). Only emit them when
          # we're inside a `routes(...)` whose prefix we already know.
          # The canonical `bind` form carries its own absolute-ish path,
          # so it stays unconditional (preserves existing behaviour).
          return false if inner_op == "bindContract" && !in_routes

          verb = resolve_verb(inner_rhs, source)
          return false unless verb

          path_text = route_path_from(inner_lhs, source, string_constants, local_string_constants)
          return false unless path_text
          emit_route(verb, join_paths(prefix, path_text), node, rhs, source, routes, include_callees)
          true
        else
          # Bare `VERB to handler` directly inside a `routes(...)` call
          # — the verbs-under-path idiom, e.g.
          #   "/{id}" bind routes(GET to Get(fs), DELETE to Delete(fs))
          # The path is supplied by the enclosing prefix; only treat it
          # as a route when we actually reached it via `routes(...)` so
          # a stray `a to b` pair elsewhere isn't misread.
          return false unless in_routes
          verb = resolve_verb(lhs, source)
          return false unless verb
          emit_route(verb, prefix.empty? ? "/" : prefix, node, rhs, source, routes, include_callees)
          true
        end
      when "bind"
        return false unless Noir::TreeSitter.node_type(rhs) == "call_expression"
        return false unless call_function_name(rhs, source) == "routes"

        path_text = resolve_string_value(lhs, source, string_constants, local_string_constants)
        return false unless path_text
        new_prefix = join_paths(prefix, path_text)
        walk_routes_args(rhs, source, new_prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, true, contract_routes)
        true
      else
        false
      end
    end

    private def emit_contract_routes(node : LibTreeSitter::TSNode,
                                     source : String,
                                     prefix : String,
                                     routes : Array(Route),
                                     contract_routes : Hash(String, Array(Route)))
      line = Noir::TreeSitter.node_start_row(node)
      contract_description_paths(node, source).each do |path|
        routes << Route.new("GET", join_paths(prefix, path), line, false, [] of String, [] of String, [] of String, [] of Tuple(String, Int32))
      end

      contract_route_references(node, source).each do |name|
        next unless helper_routes = contract_routes[name]?

        helper_routes.each do |route|
          routes << route.with_path(join_paths(prefix, route.path))
        end
      end
    end

    private def contract_description_paths(node : LibTreeSitter::TSNode, source : String) : Array(String)
      paths = [] of String
      Noir::TreeSitter.node_text(node, source).scan(/\bdescriptionPath\s*=\s*"([^"]+)"/) do |match|
        paths << match[1]
      end
      paths
    end

    private def contract_route_references(node : LibTreeSitter::TSNode, source : String) : Array(String)
      refs = [] of String
      Noir::TreeSitter.node_text(node, source).scan(/\broutes\s*\+=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |match|
        refs << match[1]
      end
      refs
    end

    # Build and append a Route from a verb, full path, and handler
    # node. Shared by the canonical `path bind VERB to handler`, the
    # contract `bindContract` form, and the bare verbs-under-path form.
    private def emit_route(verb : String,
                           full : String,
                           node : LibTreeSitter::TSNode,
                           handler : LibTreeSitter::TSNode,
                           source : String,
                           routes : Array(Route),
                           include_callees : Bool)
      line = Noir::TreeSitter.node_start_row(node)

      query, header, form = [] of String, [] of String, [] of String
      has_body = false
      scan_handler(handler, source, 0) do |kind, value|
        case kind
        when :query  then query << value
        when :header then header << value
        when :form   then form << value
        when :body   then has_body = true
        end
      end

      # http4k's routing idiom is `"/x" bind GET to handler`, not
      # `get { ... }` — there's no Ktor-style nested routing DSL
      # inside a handler body, so the routing-skip filter is off
      # to avoid silently dropping real handler calls named `get`,
      # `post`, etc.
      callees = [] of Tuple(String, Int32)
      if include_callees
        Noir::KotlinCalleeExtractor.callees_in_lambda(handler, source, "", skip_routing: false).each do |entry|
          name, _path, line_no = entry
          callees << {name, line_no}
        end
      end

      routes << Route.new(verb, full, line, has_body, query, header, form, callees)
    end

    # Resolve the path for a contract/bind LHS. Plain string literals
    # and constants resolve directly; the contract DSL wraps the path
    # in a `"/x" meta { ... }` infix, so peel the `meta` operator and
    # resolve its left operand.
    private def route_path_from(node : LibTreeSitter::TSNode,
                                source : String,
                                string_constants : Hash(String, String),
                                local_string_constants : Hash(String, String)) : String?
      if Noir::TreeSitter.node_type(node) == "infix_expression"
        l, op, _r = infix_parts(node, source)
        return unless l
        return unless op == "meta"
        return resolve_string_value(l, source, string_constants, local_string_constants)
      end
      resolve_string_value(node, source, string_constants, local_string_constants)
    end

    # Walk every argument inside a `routes(...)` call and recurse.
    # Each argument is a `value_argument` wrapping an
    # `infix_expression` (the binding) or another nested `routes(...)`
    # call.
    private def walk_routes_args(call : LibTreeSitter::TSNode,
                                 source : String,
                                 prefix : String,
                                 routes : Array(Route),
                                 string_constants : Hash(String, String),
                                 local_string_constants : Hash(String, String),
                                 depth : Int32,
                                 include_callees : Bool,
                                 in_routes : Bool,
                                 contract_routes : Hash(String, Array(Route)))
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      args = call_value_arguments(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          walk(child, source, prefix, routes, string_constants, local_string_constants, depth + 1, include_callees, in_routes, contract_routes)
        end
      end
    end

    private def collect_contract_route_functions(node : LibTreeSitter::TSNode,
                                                 source : String,
                                                 routes_by_function : Hash(String, Array(Route)),
                                                 string_constants : Hash(String, String),
                                                 local_string_constants : Hash(String, String),
                                                 include_callees : Bool,
                                                 depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "function_declaration"
        name = function_name(node, source)
        if !name.empty? && Noir::TreeSitter.node_text(node, source).includes?("bindContract")
          routes = [] of Route
          walk(node, source, "", routes, string_constants, local_string_constants, 0, include_callees, true, Hash(String, Array(Route)).new)
          routes_by_function[name] = routes unless routes.empty?
        end
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_contract_route_functions(child, source, routes_by_function, string_constants, local_string_constants, include_callees, depth + 1)
      end
    end

    private def function_name(func : LibTreeSitter::TSNode, source : String) : String
      Noir::TreeSitter.each_named_child(func) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "simple_identifier"
      end
      ""
    end

    # ---- handler-body scan ------------------------------------------

    # Look for `req.query("name")`, `req.header("X-Foo")`,
    # `req.form("name")`, `req.bodyString()` calls. We don't care
    # about the receiver name — http4k handlers conventionally use
    # `req`, but lambdas with implicit `it` or other names should
    # still surface signals.
    private def scan_handler(node : LibTreeSitter::TSNode, source : String, depth : Int32, &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      ty = Noir::TreeSitter.node_type(node)

      if ty == "call_expression"
        method = navigation_method_name(first_named_child(node), source)
        case method
        when "query"
          if value = first_string_argument(node, source)
            block.call(:query, value)
          end
        when "header"
          if value = first_string_argument(node, source)
            block.call(:header, value)
          end
        when "form"
          if value = first_string_argument(node, source)
            block.call(:form, value)
          end
        when "bodyString", "body"
          # `req.body()` returns a Body, `req.bodyString()` returns
          # a String — both indicate the handler reads the request
          # body.
          block.call(:body, "")
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, depth + 1, &block)
      end
    end

    # ---- shape helpers ----------------------------------------------

    # Pull `(lhs, operator_text, rhs)` from a Kotlin `infix_expression`.
    # Tree-sitter-kotlin lays them out as three named children: lhs,
    # operator (a `simple_identifier`), rhs. Returns nils when the
    # node doesn't look like that.
    private def infix_parts(node : LibTreeSitter::TSNode, source : String) : Tuple(LibTreeSitter::TSNode?, String, LibTreeSitter::TSNode?)
      children = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) do |child|
        children << child
      end
      return {nil, "", nil} unless children.size == 3
      lhs = children[0]
      op = Noir::TreeSitter.node_text(children[1], source)
      rhs = children[2]
      {lhs, op, rhs}
    end

    # Either a bare `simple_identifier` (`GET`) or a
    # `navigation_expression` (`Method.GET`). Returns the upper-case
    # verb name when recognised.
    private def resolve_verb(node : LibTreeSitter::TSNode, source : String) : String?
      ty = Noir::TreeSitter.node_type(node)
      candidate =
        case ty
        when "simple_identifier"
          Noir::TreeSitter.node_text(node, source)
        when "navigation_expression"
          last_navigation_segment(node, source)
        else
          ""
        end
      return if candidate.nil? || candidate.empty?
      upcased = candidate.upcase
      HTTP_VERBS.includes?(upcased) ? upcased : nil
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

    # Return the receiver-method name for a `call_expression` whose
    # callee is a `navigation_expression` (`req.query` shape).
    # Returns "" when the callee is anything else (`Response(...)`,
    # `routes(...)`, etc.).
    private def navigation_method_name(callee : LibTreeSitter::TSNode?, source : String) : String
      return "" unless callee
      return "" unless Noir::TreeSitter.node_type(callee) == "navigation_expression"
      # Only treat `<receiver>.query/header/form/body(...)` as a REQUEST
      # read when the receiver is a plain identifier (the handler's
      # `req`/`it`/`request`). A receiver that is itself a call — most
      # commonly `Response(OK).body(...)` / `Response(SEE_OTHER).header(
      # "location", ...)` — is a RESPONSE builder, and matching it would
      # mint a phantom request body/header param (notably a spurious
      # `body:json` on bodyless GET routes).
      receiver = first_named_child(callee)
      return "" unless receiver && Noir::TreeSitter.node_type(receiver) == "simple_identifier"
      last_navigation_segment(callee, source)
    end

    private def call_function_name(call : LibTreeSitter::TSNode, source : String) : String
      first = first_named_child(call)
      return "" unless first
      Noir::TreeSitter.node_type(first) == "simple_identifier" ? Noir::TreeSitter.node_text(first, source) : ""
    end

    private def call_value_arguments(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        next unless Noir::TreeSitter.node_type(child) == "call_suffix"
        Noir::TreeSitter.each_named_child(child) do |sub|
          return sub if Noir::TreeSitter.node_type(sub) == "value_arguments"
        end
      end
      nil
    end

    private def first_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = call_value_arguments(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          if Noir::TreeSitter.node_type(child) == "string_literal"
            return decode_string_literal(child, source)
          end
        end
      end
      nil
    end

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          when "interpolated_identifier", "interpolated_expression"
            io << '{'
            io << Noir::TreeSitter.node_text(child, source).strip
            io << '}'
          end
        end
      end
      buf
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
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
