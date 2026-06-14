require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./js_callee_extractor"

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

    # The only identifiers AdonisJS registers routes on: `Route` (v5,
    # `@ioc:Adonis/Core/Route`) and `router` (v6,
    # `@adonisjs/core/services/router`). Gating the verb/group/resource
    # dispatch on the call chain's ROOT receiver being one of these stops
    # every other `.get`/`.delete`/... call shaped like a route from
    # becoming a phantom endpoint — `env.get('STRIPE_SECRET_KEY')`,
    # `session.get('plan')`, a Lucid `Model.query()...delete('*')`, etc.
    ROUTER_RECEIVERS = Set{"router", "Route"}

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter callees : Array(JSCalleeExtractor::Entry)

      def initialize(@verb, @path, @line, @callees = [] of JSCalleeExtractor::Entry)
      end
    end

    def extract_routes(source : String, include_callees : Bool = false) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_javascript(source) do |root|
        walk(root, source, "", routes, 0, include_callees)
      end
      routes
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "call_expression"
        method = chain_method_name(node, source)

        # Only dispatch a recognised registration/modifier when the chain
        # is rooted on the AdonisJS router — otherwise fall through to the
        # generic recursion so a non-router call (`env.get(...)`) is not
        # mistaken for a route but nested router calls inside it are still
        # discovered.
        if dispatchable_method?(method) && router_rooted?(node, source)
          case
          when HTTP_VERB_METHODS.has_key?(method)
            emit_verb(node, source, HTTP_VERB_METHODS[method], prefix, routes, include_callees)
            return
          when method == "any"
            ANY_VERBS.each { |verb| emit_verb(node, source, verb, prefix, routes, include_callees) }
            return
          when method == "on"
            # `router.on('/path').render('view')` / `.redirect(...)` —
            # always a GET endpoint regardless of the terminator.
            emit_on(node, source, prefix, routes)
            return
          when method == GROUP_METHOD
            walk_group(node, source, prefix, routes, depth, include_callees)
            return
          when method == "resource"
            emit_resource(node, source, prefix, ANY_VERBS_ALL, routes, include_callees)
            return
          when method == "prefix"
            handle_prefix(node, source, prefix, routes, depth, include_callees)
            return
          when method == "only"
            handle_resource_filter(node, source, prefix, :only, routes, include_callees)
            return
          when method == "except"
            handle_resource_filter(node, source, prefix, :except, routes, include_callees)
            return
          when TRANSPARENT_MODIFIERS.includes?(method)
            handle_transparent(node, source, prefix, routes, depth, include_callees)
            return
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes, depth + 1, include_callees)
      end
    end

    # Sentinel meaning "all five REST actions are active" — used so
    # `emit_resource` and `handle_resource_filter` can share the
    # same emission helper without an awkward Boolean argument.
    private ANY_VERBS_ALL = ["index", "store", "show", "update", "destroy"]

    # `Route.group(cb).prefix('/x')` — capture '/x' and walk the
    # inner call's group with the joined prefix.
    private def handle_prefix(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      arg = first_string_argument(call, source)
      receiver = chain_receiver(call)
      return unless receiver

      new_prefix = arg ? join_paths(prefix, arg) : prefix
      walk(receiver, source, new_prefix, routes, depth + 1, include_callees)
    end

    private def handle_transparent(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      receiver = chain_receiver(call)
      return unless receiver
      walk(receiver, source, prefix, routes, depth + 1, include_callees)
    end

    # `.only([...])` / `.except([...])` modifiers on `.resource(...)`.
    # Walk back to the resource call with the action filter applied.
    private def handle_resource_filter(call : LibTreeSitter::TSNode, source : String, prefix : String, mode : Symbol, routes : Array(Route), include_callees : Bool)
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
      emit_resource(receiver, source, prefix, effective, routes, include_callees)
    end

    private def walk_group(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      args = arguments_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "arrow_function" ||
                    Noir::TreeSitter.node_type(arg) == "function_expression" ||
                    Noir::TreeSitter.node_type(arg) == "function"
        if body = function_body(arg)
          walk(body, source, prefix, routes, depth + 1, include_callees)
        end
      end
    end

    private def emit_verb(call : LibTreeSitter::TSNode, source : String, verb : String, prefix : String, routes : Array(Route), include_callees : Bool)
      path = first_string_argument(call, source)
      return unless path
      full = join_paths(prefix, path)
      line = Noir::TreeSitter.node_start_row(call)
      callees = include_callees ? route_callees(call, source, line) : [] of JSCalleeExtractor::Entry
      routes << Route.new(verb, full, line, callees)
    end

    private def emit_resource(call : LibTreeSitter::TSNode, source : String, prefix : String, actions : Array(String), routes : Array(Route), include_callees : Bool)
      name = first_string_argument(call, source)
      return unless name
      base = join_paths(prefix, name.starts_with?("/") ? name : "/#{name}")
      line = Noir::TreeSitter.node_start_row(call)

      actions.each do |action|
        verb_path = RESOURCE_ACTIONS[action]?
        next unless verb_path
        verb, suffix = verb_path
        url = suffix.empty? ? base : "#{base.rstrip('/')}#{suffix}"
        callees = include_callees ? [{controller_action(call, source, action), "", line + 1}] : [] of JSCalleeExtractor::Entry
        routes << Route.new(verb, url, line, callees)
      end
    end

    private def route_callees(call : LibTreeSitter::TSNode, source : String, line : Int32) : Array(JSCalleeExtractor::Entry)
      entries = [] of JSCalleeExtractor::Entry
      if controller = string_argument_at(call, source, 1)
        entries << {controller, "", line + 1}
      elsif handler = function_argument(call)
        entries = JSCalleeExtractor.callees_for_handler_node(handler, source, "")
      end
      entries
    end

    private def controller_action(call : LibTreeSitter::TSNode, source : String, action : String) : String
      controller = string_argument_at(call, source, 1) || "resource"
      "#{controller}.#{action}"
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

    # True for a trailing method name the walker knows how to handle.
    # Cheap predicate so `router_rooted?` (which descends the chain) only
    # runs for calls that could be a registration.
    private def dispatchable_method?(method : String) : Bool
      return true if HTTP_VERB_METHODS.has_key?(method)
      return true if TRANSPARENT_MODIFIERS.includes?(method)
      case method
      when "any", "on", GROUP_METHOD, "resource", "prefix", "only", "except"
        true
      else
        false
      end
    end

    # Walk the call chain down to its leftmost identifier and report
    # whether it is the AdonisJS router (`router`/`Route`). Descends
    # through member_expression receivers and chained call_expressions:
    #   router.group(cb).prefix('/x')  -> root `router`
    #   env.get('KEY')                 -> root `env`  (rejected)
    private def router_rooted?(call : LibTreeSitter::TSNode, source : String) : Bool
      root = chain_root_identifier(call)
      return false unless root
      ROUTER_RECEIVERS.includes?(Noir::TreeSitter.node_text(root, source))
    end

    private def chain_root_identifier(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      current = node
      64.times do
        case Noir::TreeSitter.node_type(current)
        when "identifier"
          return current
        when "call_expression", "member_expression"
          child = first_named_child(current)
          return unless child
          current = child
        else
          return
        end
      end
      nil
    end

    # `router.on('/path')...` always registers a GET endpoint (the
    # `.render`/`.redirect`/`.redirectToPath` terminator only decides
    # what it serves).
    private def emit_on(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      path = first_string_argument(call, source)
      return unless path
      full = join_paths(prefix, path)
      line = Noir::TreeSitter.node_start_row(call)
      routes << Route.new("GET", full, line)
    end

    private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end

    private def first_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
      string_argument_at(call, source, 0)
    end

    private def string_argument_at(call : LibTreeSitter::TSNode, source : String, target_index : Int32) : String?
      args = arguments_node(call)
      return unless args
      index = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "string"
        return decode_string(arg, source) if index == target_index
        index += 1
      end
      nil
    end

    private def function_argument(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = arguments_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        type = Noir::TreeSitter.node_type(arg)
        return arg if type == "arrow_function" || type == "function_expression" || type == "function"
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
