require "../utils/url_path"
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
  #   * `.resource(name, controller)` — emits the seven resourceful
  #     routes (index / create / store / show / edit / update as PUT and
  #     PATCH / destroy); `.apiOnly()` drops the `create` and `edit`
  #     form routes, `.only([...])` restricts to the listed actions and
  #     `.except` drops the listed ones. A dotted name nests:
  #     `posts.comments` is `/posts/:post_id/comments`.
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

    # {action, verb, suffix} in AdonisJS's own registration order.
    RESOURCE_ACTIONS = [
      {"index", "GET", ""},
      {"create", "GET", "/create"},
      {"store", "POST", ""},
      {"show", "GET", "/:id"},
      {"edit", "GET", "/:id/edit"},
      {"update", "PUT", "/:id"},
      {"update", "PATCH", "/:id"},
      {"destroy", "DELETE", "/:id"},
    ]
    RESOURCE_ACTION_NAMES = RESOURCE_ACTIONS.map(&.[0]).uniq!
    # The HTML form routes `.apiOnly()` removes.
    FORM_ACTIONS = ["create", "edit"]
    # Chain links that narrow a resource's action set.
    RESOURCE_FILTERS = Set{"only", "except", "apiOnly"}

    # Modifiers that don't change the path or verb — we just walk
    # the receiver with the same prefix.
    TRANSPARENT_MODIFIERS = Set{
      "middleware", "as", "domain", "where", "namespace",
    }

    # The only identifiers AdonisJS registers routes on: `Route` (v5,
    # `@ioc:Adonis/Core/Route`) and `router` (v6,
    # `@adonisjs/core/services/router`). Gating the verb/group/resource
    # dispatch on the call chain's ROOT receiver being one of these stops
    # every other `.get`/`.delete`/... call shaped like a route from
    # becoming a phantom endpoint — `env.get('STRIPE_SECRET_KEY')`,
    # `session.get('plan')`, a Lucid `Model.query()...delete('*')`, etc.
    ROUTER_RECEIVERS = Set{"router", "Route"}

    # Route paths and controller references are written as either a quoted
    # string or a backtick template literal — tree-sitter-javascript emits
    # `template_string` for the latter. `decode_string` has always known how
    # to unwrap both; only the call-site gates were rejecting backticks.
    STRING_LITERAL_TYPES = Set{"string", "template_string"}

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
          when method == "resource" || RESOURCE_FILTERS.includes?(method)
            emit_resource_chain(node, source, prefix, routes, include_callees) ||
              handle_transparent(node, source, prefix, routes, depth, include_callees)
            return
          when method == "prefix"
            handle_prefix(node, source, prefix, routes, depth, include_callees)
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

    # `Route.group(cb).prefix('/x')` — capture '/x' and walk the
    # inner call's group with the joined prefix.
    private def handle_prefix(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      arg = first_string_argument(call, source)
      receiver = chain_receiver(call)
      return unless receiver

      new_prefix = arg ? Noir::URLPath.join_trimmed(prefix, arg) : prefix
      walk(receiver, source, new_prefix, routes, depth + 1, include_callees)
    end

    private def handle_transparent(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), depth : Int32, include_callees : Bool)
      receiver = chain_receiver(call)
      return unless receiver
      walk(receiver, source, prefix, routes, depth + 1, include_callees)
    end

    # `.resource(...)` and every link chained on it (`.apiOnly()`,
    # `.only([...])`, `.except([...])`, `.as(...)`, `.use(...)`, in any
    # order): walk down to the resource call, narrowing the action set at
    # each filter. False when the chain is not rooted on a resource.
    private def emit_resource_chain(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route), include_callees : Bool) : Bool
      actions = RESOURCE_ACTION_NAMES.dup
      node = call
      until (method = chain_method_name(node, source)) == "resource"
        case method
        when "only"   then actions &= string_array_arg(node, source)
        when "except" then actions -= string_array_arg(node, source)
        when "apiOnly"
          actions -= FORM_ACTIONS
        end
        node = chain_receiver(node) || return false
        return false unless Noir::TreeSitter.node_type(node) == "call_expression"
      end
      emit_resource(node, source, prefix, actions, routes, include_callees)
      true
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
      full = Noir::URLPath.join_trimmed(prefix, path)
      line = Noir::TreeSitter.call_name_row(call)
      callees = include_callees ? route_callees(call, source, line) : [] of JSCalleeExtractor::Entry
      routes << Route.new(verb, full, line, callees)
    end

    private def emit_resource(call : LibTreeSitter::TSNode, source : String, prefix : String, actions : Array(String), routes : Array(Route), include_callees : Bool)
      name = first_string_argument(call, source)
      return unless name
      base = Noir::URLPath.join_trimmed(prefix, "/#{resource_path(name.lchop('/'))}")
      line = Noir::TreeSitter.call_name_row(call)

      RESOURCE_ACTIONS.each do |action, verb, suffix|
        next unless actions.includes?(action)
        url = suffix.empty? ? base : "#{base.rstrip('/')}#{suffix}"
        callees = include_callees ? [{controller_action(call, source, action), "", line + 1}] : [] of JSCalleeExtractor::Entry
        routes << Route.new(verb, url, line, callees)
      end
    end

    # `posts.comments` → `posts/:post_id/comments`: each parent segment is
    # followed by its singular, snake_cased `_id` param, as AdonisJS names it.
    private def resource_path(name : String) : String
      *parents, main = name.split('.')
      parents.map { |parent| "#{parent}/:#{singular(parent).underscore.tr("-", "_")}_id" }.push(main).join('/')
    end

    # ponytail: English plural rules for the common cases; an irregular
    # plural only misnames the placeholder, never the route structure.
    private def singular(word : String) : String
      return "#{word[0...-3]}y" if word.ends_with?("ies") && word.size > 3
      return word[0...-1] if word.ends_with?('s') && !word.ends_with?("ss")
      word
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
      callee = Noir::TreeSitter.first_named_child(call)
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
      callee = Noir::TreeSitter.first_named_child(call)
      return unless callee
      return unless Noir::TreeSitter.node_type(callee) == "member_expression"
      Noir::TreeSitter.first_named_child(callee)
    end

    # True for a trailing method name the walker knows how to handle.
    # Cheap predicate so `router_rooted?` (which descends the chain) only
    # runs for calls that could be a registration.
    private def dispatchable_method?(method : String) : Bool
      return true if HTTP_VERB_METHODS.has_key?(method)
      return true if TRANSPARENT_MODIFIERS.includes?(method)
      case method
      when "any", "on", GROUP_METHOD, "resource", "prefix", "only", "except", "apiOnly"
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
          child = Noir::TreeSitter.first_named_child(current)
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
      full = Noir::URLPath.join_trimmed(prefix, path)
      line = Noir::TreeSitter.call_name_row(call)
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

    # Index over EVERY argument, not only the string-shaped ones.
    # Counting string nodes alone made the positions depend on which
    # arguments happened to be strings, so a non-string first argument
    # silently promoted the second one:
    # `Route.get(`/users/${id}`, 'UsersController.show')` used to report
    # `GET /UsersController.show` — a URL that exists nowhere in the app —
    # because the template literal was invisible to this counter and the
    # controller string landed on index 0.
    private def string_argument_at(call : LibTreeSitter::TSNode, source : String, target_index : Int32) : String?
      args = arguments_node(call)
      return unless args
      index = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        type = Noir::TreeSitter.node_type(arg)
        next if type == "comment"
        if index == target_index
          return STRING_LITERAL_TYPES.includes?(type) ? decode_string(arg, source) : nil
        end
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

    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          when "escape_sequence"
            io << Noir::TreeSitter.unescape(Noir::TreeSitter.node_text(child, source))
          when "template_substitution"
            # `` `/users/${id}` `` — keep the hole as a `{id}` placeholder
            # rather than dropping it, which would collapse the path to
            # `/users/` (or `/users//edit` for an interior hole). Same
            # convention the Python f-string and Kotlin template decoders
            # use, and the shape downstream path-param extraction expects.
            io << Noir::TreeSitter.node_text(child, source).lchop('$')
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
  end
end
