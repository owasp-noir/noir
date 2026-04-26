require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed AdonisJS extractor.
  #
  # AdonisJS exposes a Laravel-flavoured router via either `Route`
  # (v5, `@ioc:Adonis/Core/Route`) or `router` (v6,
  # `@adonisjs/core/services/router`). Both share the same shape:
  #
  # ```
  # Route.get('/users', 'UsersController.index')
  #
  # Route.group(() => {
  #     Route.get('/posts', 'PostsController.index')
  #     Route.post('/posts', 'PostsController.store')
  # }).prefix('/api/v1').middleware('auth')
  #
  # Route.resource('articles', 'ArticlesController').apiOnly()
  # ```
  #
  # The fluent modifiers (`.prefix`, `.middleware`, `.as`, `.domain`,
  # `.namespace`, `.where`, `.apiOnly`, `.only`, `.except`) live on
  # the result of the registration call. We walk the chain
  # outermost-first so the modifiers can influence the prefix /
  # resource action set before the inner registration emits.
  #
  # Recognised:
  #
  #   * Verb methods: `.get`, `.post`, `.put`, `.delete`, `.patch`,
  #     `.options`, `.head`, plus `.any` (fans out to GET / POST /
  #     PUT / DELETE / PATCH).
  #   * `.group(callback)` — walks the callback with the current
  #     accumulated prefix; subsequent `.prefix(...)` modifiers on
  #     the group result are folded in.
  #   * `.resource(name, controller)` — emits the five REST API
  #     routes (index / store / show / update / destroy). The
  #     `.apiOnly()` modifier is the default behaviour here;
  #     `.only([...])` restricts to the listed actions; `.except`
  #     drops the listed ones.
  #
  # Out of scope for this first cut:
  #
  #   * Per-handler request-helper scanning. AdonisJS handlers
  #     receive `({ request, response, params })` — the dominant
  #     pattern is to point at a `'Controller.method'` string,
  #     which would need cross-file resolution to scan.
  #   * `.where('id', /\d+/)` constraint annotations beyond
  #     stripping the modifier.
  #   * Domain / subdomain routing.
  module TreeSitterAdonisJsExtractor
    extend self

    HTTP_VERB_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "options" => "OPTIONS",
      "head"    => "HEAD",
    }

    ANY_VERBS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    GROUP_METHOD = "group"

    RESOURCE_ACTIONS = {
      "index"   => {"GET", ""},
      "store"   => {"POST", ""},
      "show"    => {"GET", "/:id"},
      "update"  => {"PUT", "/:id"},
      "destroy" => {"DELETE", "/:id"},
    }

    # Modifiers that don't change the path or verb — we just walk
    # the receiver with the same prefix.
    TRANSPARENT_MODIFIERS = Set{
      "middleware", "as", "domain", "where", "namespace", "apiOnly",
    }

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32

      def initialize(@verb, @path, @line)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_javascript(source) do |root|
        walk(root, source, "", routes, 0)
      end
      routes
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "call_expression"
        method = chain_method_name(node, source)

        case
        when HTTP_VERB_METHODS.has_key?(method)
          emit_verb(node, source, HTTP_VERB_METHODS[method], prefix, routes)
          return
        when method == "any"
          ANY_VERBS.each { |verb| emit_verb(node, source, verb, prefix, routes) }
          return
        when method == GROUP_METHOD
          walk_group(node, source, prefix, routes, depth)
          return
        when method == "resource"
          emit_resource(node, source, prefix, ANY_VERBS_ALL, routes)
          return
        when method == "prefix"
          handle_prefix(node, source, prefix, routes, depth)
          return
        when method == "only"
          handle_resource_filter(node, source, prefix, :only, routes)
          return
        when method == "except"
          handle_resource_filter(node, source, prefix, :except, routes)
          return
        when TRANSPARENT_MODIFIERS.includes?(method)
          handle_transparent(node, source, prefix, routes, depth)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, depth + 1)
      end
    end

    # Sentinel meaning "all five REST actions are active" — used so
    # `emit_resource` and `handle_resource_filter` can share the
    # same emission helper without an awkward Boolean argument.
    private ANY_VERBS_ALL = ["index", "store", "show", "update", "destroy"]

    # `Route.group(cb).prefix('/x')` — capture '/x' and walk the
    # inner call's group with the joined prefix.
    private def handle_prefix(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      arg = first_string_argument(call, source)
      receiver = chain_receiver(call)
      return unless receiver

      new_prefix = arg ? join_paths(prefix, arg) : prefix
      walk(receiver, source, new_prefix, routes, depth + 1)
    end

    private def handle_transparent(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      receiver = chain_receiver(call)
      return unless receiver
      walk(receiver, source, prefix, routes, depth + 1)
    end

    # `.only([...])` / `.except([...])` modifiers on `.resource(...)`.
    # Walk back to the resource call with the action filter applied.
    private def handle_resource_filter(call : LibTreeSitter::TSNode, source : String, prefix : String, mode : Symbol, routes : Array(Route))
      receiver = chain_receiver(call)
      return unless receiver
      return unless Noir::TreeSitter.node_type(receiver) == "call_expression"
      return unless chain_method_name(receiver, source) == "resource"

      action_names = string_array_arg(call, source)
      effective =
        case mode
        when :only
          ANY_VERBS_ALL.select { |a| action_names.includes?(a) }
        when :except
          ANY_VERBS_ALL.reject { |a| action_names.includes?(a) }
        else
          ANY_VERBS_ALL
        end
      emit_resource(receiver, source, prefix, effective, routes)
    end

    private def walk_group(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32)
      args = arguments_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "arrow_function" ||
                    Noir::TreeSitter.node_type(arg) == "function_expression" ||
                    Noir::TreeSitter.node_type(arg) == "function"
        if body = function_body(arg)
          walk(body, source, prefix, routes, depth + 1)
        end
      end
    end

    private def emit_verb(call : LibTreeSitter::TSNode, source : String, verb : String, prefix : String, routes : Array(Route))
      path = first_string_argument(call, source)
      return unless path
      full = join_paths(prefix, path)
      line = Noir::TreeSitter.node_start_row(call)
      routes << Route.new(verb, full, line)
    end

    private def emit_resource(call : LibTreeSitter::TSNode, source : String, prefix : String, actions : Array(String), routes : Array(Route))
      name = first_string_argument(call, source)
      return unless name
      base = join_paths(prefix, name.starts_with?("/") ? name : "/#{name}")
      line = Noir::TreeSitter.node_start_row(call)

      actions.each do |action|
        verb_path = RESOURCE_ACTIONS[action]?
        next unless verb_path
        verb, suffix = verb_path
        url = suffix.empty? ? base : "#{base.rstrip('/')}#{suffix}"
        routes << Route.new(verb, url, line)
      end
    end

    # ---- shape helpers ----------------------------------------------

    # `Route.get(...)` and `Route.group(...).prefix(...)` both
    # produce call_expressions whose callee is a member_expression
    # ending in a `property_identifier`. Return that property name;
    # empty string when the callee is a bare identifier
    # (`foo(...)` — not in our shape).
    private def chain_method_name(call : LibTreeSitter::TSNode, source : String) : String
      callee = first_named_child(call)
      return "" unless callee
      return "" unless Noir::TreeSitter.node_type(callee) == "member_expression"
      Noir::TreeSitter.each_named_child(callee) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "property_identifier"
      end
      ""
    end

    # The receiver in a chain (the previous `call_expression` link)
    # is the first child of the callee `member_expression`.
    private def chain_receiver(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      callee = first_named_child(call)
      return unless callee
      return unless Noir::TreeSitter.node_type(callee) == "member_expression"
      first_named_child(callee)
    end

    private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end

    private def first_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = arguments_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        return decode_string(arg, source) if Noir::TreeSitter.node_type(arg) == "string"
      end
      nil
    end

    private def string_array_arg(call : LibTreeSitter::TSNode, source : String) : Array(String)
      result = [] of String
      args = arguments_node(call)
      return result unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "array"
        Noir::TreeSitter.each_named_child(arg) do |elem|
          if Noir::TreeSitter.node_type(elem) == "string"
            result << decode_string(elem, source)
          end
        end
      end
      result
    end

    private def function_body(fn : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      seen_params = false
      Noir::TreeSitter.each_named_child(fn) do |child|
        ty = Noir::TreeSitter.node_type(child)
        if !seen_params && (ty == "formal_parameters" || ty == "identifier")
          seen_params = true
          next
        end
        return child if seen_params
      end
      nil
    end

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      if raw.size >= 2 && (raw[0] == '\'' || raw[0] == '"' || raw[0] == '`') && raw[0] == raw[-1]
        raw[1..-2]
      else
        raw
      end
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
