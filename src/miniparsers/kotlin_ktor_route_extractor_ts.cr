require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

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
      getter query_params : Array(String)
      getter header_params : Array(String)

      def initialize(@verb, @path, @line, @receive_type, @query_params, @header_params)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_kotlin(source) do |root|
        walk(root, source, "", routes)
      end
      routes
    end

    # ---- traversal ----------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      if Noir::TreeSitter.node_type(node) == "call_expression"
        name = call_name(node, source)
        case
        when HTTP_VERB_NAMES.has_key?(name)
          emit_route(node, source, name, prefix, routes)
          return
        when name == "route"
          path_arg = call_string_argument(node, source)
          new_prefix = path_arg ? prefix + path_arg : prefix
          if body = call_lambda_body(node)
            walk(body, source, new_prefix, routes)
          end
          return
        when PASSTHROUGH_NAMES.includes?(name)
          if body = call_lambda_body(node)
            walk(body, source, prefix, routes)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes)
      end
    end

    private def emit_route(node : LibTreeSitter::TSNode, source : String, name : String, prefix : String, routes : Array(Route))
      path_arg = call_string_argument(node, source)
      return unless path_arg

      verb = HTTP_VERB_NAMES[name]
      full_path = prefix + path_arg
      line = Noir::TreeSitter.node_start_row(node)

      receive_type : String? = nil
      query_params = [] of String
      header_params = [] of String

      if body = call_lambda_body(node)
        scan_handler_body(body, source, query_params, header_params).tap do |rt|
          receive_type = rt
        end
      end

      routes << Route.new(verb, full_path, line, receive_type, query_params, header_params)
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
      else
        ""
      end
    end

    # Pull the first `string_literal` argument, if any, from the inner
    # call. Used for `get("/x")` and `route("/api")`.
    private def call_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
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
          if Noir::TreeSitter.node_type(child) == "string_literal"
            return decode_string_literal(child, source)
          end
        end
      end
      nil
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
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_content"
            io << Noir::TreeSitter.node_text(child, source)
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
                                  header_params : Array(String)) : String?
      receive_type : String? = nil
      walk_handler(node, source, query_params, header_params) do |type|
        receive_type ||= type
      end
      receive_type
    end

    private def walk_handler(node : LibTreeSitter::TSNode,
                             source : String,
                             query_params : Array(String),
                             header_params : Array(String),
                             &block : String ->)
      ty = Noir::TreeSitter.node_type(node)

      case ty
      when "call_expression"
        if call_is_call_receive?(node, source)
          if type_arg = call_receive_type_argument(node, source)
            block.call(type_arg)
          end
          return
        end
      when "indexing_expression"
        target = first_named_child(node)
        if target
          chain = navigation_chain(target, source)
          if chain == ["call", "parameters"]
            if name = indexing_string_key(node, source)
              query_params << name
            end
          elsif chain == ["call", "request", "headers"]
            if name = indexing_string_key(node, source)
              header_params << name
            end
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_handler(child, source, query_params, header_params, &block)
      end
    end

    private def call_is_call_receive?(call : LibTreeSitter::TSNode, source : String) : Bool
      first = first_named_child(call)
      return false unless first
      return false unless Noir::TreeSitter.node_type(first) == "navigation_expression"
      navigation_chain(first, source) == ["call", "receive"]
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
    # chain to its `type_identifier` leaf.
    private def type_leaf(node : LibTreeSitter::TSNode, source : String) : String?
      ty = Noir::TreeSitter.node_type(node)
      return Noir::TreeSitter.node_text(node, source) if ty == "type_identifier"

      Noir::TreeSitter.each_named_child(node) do |child|
        if leaf = type_leaf(child, source)
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
  end
end
