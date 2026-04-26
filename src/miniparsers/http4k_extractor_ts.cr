require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

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

      def initialize(@verb, @path, @line, @has_body,
                     @query_params, @header_params, @form_params)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk(root, source, "", routes, 0)
      end
      routes
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "infix_expression" && handle_bind(node, source, prefix, routes, depth)
        return
      end

      if ty == "call_expression" && call_function_name(node, source) == "routes"
        walk_routes_args(node, source, prefix, routes, depth)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, depth + 1)
      end
    end

    # Try to interpret an `infix_expression` as one of:
    #
    #   - `path bind VERB to handler` — emit a route.
    #   - `path bind routes(...)`     — prefix composition; recurse.
    #
    # Returns true when consumed; false otherwise so the caller can
    # fall through to the generic descent.
    private def handle_bind(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32) : Bool
      lhs, op, rhs = infix_parts(node, source)
      return false unless lhs && rhs

      case op
      when "to"
        # Outer node — inner must be `path bind VERB`.
        return false unless Noir::TreeSitter.node_type(lhs) == "infix_expression"
        inner_lhs, inner_op, inner_rhs = infix_parts(lhs, source)
        return false unless inner_op == "bind"
        return false unless inner_lhs && inner_rhs
        return false unless Noir::TreeSitter.node_type(inner_lhs) == "string_literal"

        verb = resolve_verb(inner_rhs, source)
        return false unless verb

        path_text = decode_string_literal(inner_lhs, source)
        full = join_paths(prefix, path_text)
        line = Noir::TreeSitter.node_start_row(node)

        query, header, form = [] of String, [] of String, [] of String
        has_body = false
        scan_handler(rhs, source, 0) do |kind, value|
          case kind
          when :query  then query << value
          when :header then header << value
          when :form   then form << value
          when :body   then has_body = true
          end
        end

        routes << Route.new(verb, full, line, has_body, query, header, form)
        true
      when "bind"
        return false unless Noir::TreeSitter.node_type(lhs) == "string_literal"
        return false unless Noir::TreeSitter.node_type(rhs) == "call_expression"
        return false unless call_function_name(rhs, source) == "routes"

        path_text = decode_string_literal(lhs, source)
        new_prefix = join_paths(prefix, path_text)
        walk_routes_args(rhs, source, new_prefix, routes, depth + 1)
        true
      else
        false
      end
    end

    # Walk every argument inside a `routes(...)` call and recurse.
    # Each argument is a `value_argument` wrapping an
    # `infix_expression` (the binding) or another nested `routes(...)`
    # call.
    private def walk_routes_args(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      args = call_value_arguments(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "value_argument"
        Noir::TreeSitter.each_named_child(arg) do |child|
          walk(child, source, prefix, routes, depth + 1)
        end
      end
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
          if Noir::TreeSitter.node_type(child) == "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      buf
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
