# Part of Noir::TreeSitterGoRouteExtractor: chi's Route/Mount/With tree walker.
module Noir
  module TreeSitterGoRouteExtractor
    # net/http-style registrations chi exposes alongside the verb
    # shortcuts: `r.MethodFunc("GET", "/x", h)` (method as the first
    # string arg, incl. custom verbs from `chi.RegisterMethod`) and
    # `r.HandleFunc("/x", h)` / `r.Handle("/x", h)` (match ANY method).
    # Gated behind `ScopedConfig#net_http_methods?` so the gf walker —
    # which shares this recognizer — is untouched.
    def extract_chi_routes(source : String,
                           skip_functions : Set(String) = Set(String).new,
                           external_string_values : Hash(String, String) = Hash(String, String).new) : Array(Route)
      extract_scoped_routes(source, ScopedConfig.new(net_http_methods: true), skip_functions, external_string_values)
    end

    # Exposes the closure-scoped walker against an arbitrary node
    # (typically a function body captured elsewhere). Uses chi defaults
    # incl. the net/http registrations (MethodFunc/HandleFunc/Handle) so a
    # Mount-expanded router function body is parsed like any chi file.
    def walk_chi_public(node : LibTreeSitter::TSNode,
                        source : String,
                        sink : Array(Route),
                        string_values : Hash(String, String) = Hash(String, String).new,
                        helpers : RouteHelperIndex = RouteHelperIndex.new)
      local_groups = Hash(String, String).new
      skip = Set(String).new
      walk_chi(node, source, [] of String, local_groups, sink, skip, ScopedConfig.new(net_http_methods: true), string_values, helpers)
    end

    # A same-file function (or closure variable) that takes the router as
    # a parameter and registers routes on it — gitea's
    # `func addProjectRoutes(m *web.Router, ...)` called from three
    # different groups, or `addActionsRoutes := func(m *web.Router, ...)`.
    # Its body is walked at every call site with the caller's active
    # prefix, and its declaration is skipped by the free-floating walk
    # (which would otherwise report the routes at the helper's own,
    # prefix-less, path).
    class RouteHelper
      getter body : LibTreeSitter::TSNode
      getter router_param : String
      getter router_index : Int32
      property calls : Int32 = 0

      def initialize(@body, @router_param, @router_index)
      end
    end

    class RouteHelperIndex
      getter helpers = Hash(String, RouteHelper).new
      # Helpers whose bodies are being expanded right now (recursion guard).
      getter active = Set(String).new

      def empty? : Bool
        helpers.empty?
      end

      def [](name : String) : RouteHelper?
        helpers[name]?
      end
    end

    # Router-typed parameter: `*web.Router`, `chi.Router`, `*chi.Mux`,
    # `*Router`. `http.ServeMux` is deliberately not one (its `Mux` is not
    # a whole segment) — helpers taking a stdlib mux register net/http
    # handlers, not chi routes.
    ROUTER_PARAM_TYPE_RE = /\A\*?(?:\w+\.)?(?:Router|Mux)\z/

    # Scan a whole file for route helpers and count their call sites.
    # Only a helper that is called at least once is skipped by the free
    # walk; an uncalled one keeps its historical (prefix-less) routes so
    # nothing that used to be reported disappears.
    def collect_route_helpers(root : LibTreeSitter::TSNode, source : String) : RouteHelperIndex
      index = RouteHelperIndex.new
      walk(root) do |node|
        case Noir::TreeSitter.node_type(node)
        when "function_declaration"
          name_node = Noir::TreeSitter.field(node, "name")
          body = Noir::TreeSitter.field(node, "body")
          next unless name_node && body
          if param = router_parameter(node, source)
            index.helpers[Noir::TreeSitter.node_text(name_node, source)] = RouteHelper.new(body, param[0], param[1])
          end
        when "short_var_declaration"
          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          next unless left && right
          name_node = first_named_child(left)
          closure = first_named_child(right)
          next unless name_node && closure
          next unless Noir::TreeSitter.node_type(name_node) == "identifier"
          next unless Noir::TreeSitter.node_type(closure) == "func_literal"
          body = Noir::TreeSitter.field(closure, "body")
          next unless body
          if param = router_parameter(closure, source)
            index.helpers[Noir::TreeSitter.node_text(name_node, source)] = RouteHelper.new(body, param[0], param[1])
          end
        end
      end
      return index if index.empty?
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        function = Noir::TreeSitter.field(node, "function")
        next unless function && Noir::TreeSitter.node_type(function) == "identifier"
        if helper = index[Noir::TreeSitter.node_text(function, source)]
          helper.calls += 1
        end
      end
      index
    end

    # `{name, position}` of the first router-typed parameter of a
    # function declaration or func literal, or nil.
    private def router_parameter(func : LibTreeSitter::TSNode, source : String) : Tuple(String, Int32)?
      params = Noir::TreeSitter.field(func, "parameters")
      return unless params
      position = 0
      Noir::TreeSitter.each_named_child(params) do |decl|
        if Noir::TreeSitter.node_type(decl) == "parameter_declaration"
          type_node = Noir::TreeSitter.field(decl, "type")
          names = [] of String
          Noir::TreeSitter.each_named_child(decl) do |child|
            names << Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
          end
          if type_node && !names.empty? && Noir::TreeSitter.node_text(type_node, source).matches?(ROUTER_PARAM_TYPE_RE)
            return {names.first, position}
          end
          # `a, b *T` declares several names in one declaration.
          position += names.empty? ? 1 : names.size
        else
          position += 1
        end
      end
      nil
    end

    # Walk a helper's body as if its routes were registered at the call
    # site: the router argument's active prefix becomes the base prefix
    # and the helper's own parameter name resolves through the stack.
    private def expand_route_helper(call : LibTreeSitter::TSNode,
                                    helper : RouteHelper,
                                    name : String,
                                    source : String,
                                    prefix_stack : Array(String),
                                    local_groups : Hash(String, String),
                                    routes : Array(Route),
                                    skip_functions : Set(String),
                                    config : ScopedConfig,
                                    string_values : Hash(String, String),
                                    helpers : RouteHelperIndex)
      return if helpers.active.includes?(name) || helpers.active.size >= 8
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      router_arg = nil
      position = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        if position == helper.router_index
          router_arg = arg
          break
        end
        position += 1
      end
      return unless router_arg
      return unless Noir::TreeSitter.node_type(router_arg) == "identifier"
      router_name = Noir::TreeSitter.node_text(router_arg, source)
      base_prefix = local_groups[router_name]? || prefix_stack.join

      inner_groups = local_groups.dup
      inner_groups.delete(helper.router_param)
      helpers.active << name
      walk_chi(helper.body, source, [base_prefix], inner_groups, routes, skip_functions, config, string_values, helpers)
      helpers.active.delete(name)
    end

    private def walk_chi(node : LibTreeSitter::TSNode,
                         source : String,
                         prefix_stack : Array(String),
                         local_groups : Hash(String, String),
                         routes : Array(Route),
                         skip_functions : Set(String),
                         config : ScopedConfig,
                         string_values : Hash(String, String) = Hash(String, String).new,
                         helpers : RouteHelperIndex = RouteHelperIndex.new)
      ty = Noir::TreeSitter.node_type(node)

      # A called route helper is expanded at its call sites, never at
      # its declaration (see `RouteHelper`).
      unless helpers.empty?
        case ty
        when "function_declaration"
          if name_node = Noir::TreeSitter.field(node, "name")
            if (helper = helpers[Noir::TreeSitter.node_text(name_node, source)]) && helper.calls > 0
              return
            end
          end
        when "short_var_declaration"
          if (left = Noir::TreeSitter.field(node, "left")) && (name_node = first_named_child(left))
            if (helper = helpers[Noir::TreeSitter.node_text(name_node, source)]) && helper.calls > 0
              return
            end
          end
        when "call_expression"
          if (function = Noir::TreeSitter.field(node, "function")) && Noir::TreeSitter.node_type(function) == "identifier"
            name = Noir::TreeSitter.node_text(function, source)
            if helper = helpers[name]
              expand_route_helper(node, helper, name, source, prefix_stack, local_groups, routes, skip_functions, config, string_values, helpers)
              return
            end
          end
        end
      end

      # Skip `func <skipped>() { ... }` bodies entirely — their routes are
      # emitted by a separate analysis pass (e.g. Mount expansion). A plain
      # function (`func adminRouter()`) is keyed by its bare name; a method
      # (`func (rs todosResource) Routes()`) is keyed by `Receiver.Method`
      # so ONLY the exact mounted method body is skipped — a same-named
      # method on another type, or a top-level router builder also named
      # `Routes()` used directly, keeps its routes (and the `.Mount`
      # calls inside it).
      if (ty == "function_declaration" || ty == "method_declaration") && !skip_functions.empty?
        if name_node = Noir::TreeSitter.field(node, "name")
          name = Noir::TreeSitter.node_text(name_node, source)
          skip_key = if ty == "method_declaration"
                       if (recv = Noir::TreeSitter.field(node, "receiver")) && (rt = receiver_type_name(recv, source))
                         "#{rt}.#{name}"
                       end
                     else
                       name
                     end
          return if skip_key && skip_functions.includes?(skip_key)
        end
      end

      # `v1 := group.Group("/v1")` inside a closure binds `v1` to the
      # combined prefix. We use `local_groups` instead of `prefix_stack`
      # here because the binding is name-scoped: sibling calls on the
      # outer receiver still refer to the outer prefix.
      if ty == "short_var_declaration"
        bind_local_group(node, source, local_groups, config, string_values)
      end

      if ty == "call_expression"
        kind = classify_chi_call(node, source, config, string_values)
        case kind
        when ChiCall::Route
          if info = unpack_chi_scope_call(node, source, string_values, expect_prefix: true)
            new_prefix, body, closure = info
            prefix_stack.push(new_prefix)
            # Register the closure's first router param (e.g. `group` in
            # `.Group("/api", func(group *ghttp.RouterGroup) {...})`) as
            # an alias to the *full* active prefix (stack joined), so a
            # nested `Route("/{articleID}", func(r chi.Router){...})`
            # binds `r` to `/articles/{articleID}`, not just
            # `/{articleID}`.
            param_name = extract_closure_first_param_name(closure, source)
            active_prefix = prefix_stack.join
            saved_binding = local_groups[param_name]? if param_name
            local_groups[param_name] = active_prefix if param_name
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config, string_values, helpers)
            if param_name
              if saved_binding.nil?
                local_groups.delete(param_name)
              else
                local_groups[param_name] = saved_binding
              end
            end
            prefix_stack.pop
            return
          end
        when ChiCall::Group
          if info = unpack_chi_scope_call(node, source, string_values, expect_prefix: false)
            _, body, _ = info
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config, string_values, helpers)
            return
          end
        when ChiCall::Verb
          # `m.Combo("/x").Get(h).Post(h)` — one path, several verbs,
          # each on its own chained call. The outermost call is the
          # last verb; peel the chain down to `Combo` first, and only
          # fall back to the single-verb decoder when there is none.
          if combo = decode_chi_combo_chain(node, source, prefix_stack, local_groups, string_values)
            routes.concat(combo)
            return
          end
          if route = decode_chi_verb_call(node, source, prefix_stack, local_groups, config, string_values)
            routes << route
          end
          return
        when ChiCall::Bind
          if route = decode_chi_bind_call(node, source, prefix_stack, local_groups, config, string_values)
            routes << route
          end
          return
        when ChiCall::MethodFunc
          if route = decode_chi_methodfunc_call(node, source, prefix_stack, local_groups, string_values)
            routes << route
          end
          return
        when ChiCall::HandleAll
          if route = decode_chi_handle_all_call(node, source, prefix_stack, local_groups, string_values)
            routes << route
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_chi(child, source, prefix_stack, local_groups, routes, skip_functions, config, string_values, helpers)
      end
    end

    # Classify a call_expression so `walk_chi` knows whether to descend
    # into a scoped body, emit a route, or keep walking children.
    private def classify_chi_call(call : LibTreeSitter::TSNode, source : String, config : ScopedConfig,
                                  string_values : Hash(String, String) = Hash(String, String).new) : ChiCall
      function = Noir::TreeSitter.field(call, "function")
      return ChiCall::None unless function
      return ChiCall::None unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return ChiCall::None unless field
      name = Noir::TreeSitter.node_text(field, source)

      if name == config.prefix_method
        # (string, closure) -> push prefix. This also handles gf's
        # `.Group("/api", func(){...})`.
        if chi_first_string_arg(call, source, string_values) && chi_closure_arg(call)
          return ChiCall::Route
        end
      end

      if (mw = config.middleware_method) && name == mw
        if chi_closure_arg(call)
          if chi_first_string_arg(call, source, string_values)
            # (string, closure) -> push prefix. Chi's own `Group` takes no
            # path, but wrappers like gitea's `code.gitea.io/gitea/modules/web`
            # expose `m.Group("/path", func(){...})` — a path-scoped group.
            # Treat that form like `Route` so the prefix composes onto the
            # routes nested inside (gitea/gogs/forgejo register the bulk of
            # their tree this way).
            return ChiCall::Route
          else
            # (closure only) -> middleware group that doesn't change prefix.
            # Excludes Gin-style `.Group("/x")` (no closure) which is handled
            # by `extract_routes`, not this walker.
            return ChiCall::Group
          end
        end
      end

      if config.bind_methods.includes?(name)
        return ChiCall::Bind
      end

      case name
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "ALL",
           "Get", "Post", "Put", "Delete", "Patch", "Head", "Options"
        return ChiCall::Verb
      end

      if config.net_http_methods?
        # `r.MethodFunc("GET", "/x", h)` — method as the first string
        # arg (the route path is the second). Also covers custom verbs
        # registered via `chi.RegisterMethod`. gitea's `modules/web`
        # wrapper spells the same shape `m.Methods("GET, HEAD", "/x", h)`
        # with a comma-separated method list.
        return ChiCall::MethodFunc if name == "MethodFunc" || name == "Methods"
        # `r.HandleFunc("/x", h)` / `r.Handle("/x", h)` — match every
        # HTTP method (chi fans these over the full method set).
        return ChiCall::HandleAll if name == "HandleFunc" || name == "Handle"
      end

      ChiCall::None
    end

    # Decode `<router>.<bind_method>("/path", handler)` — for gf's
    # BindHandler/BindMiddleware-style registration. Emits a single
    # Route with a fan-out verb (default "ALL"); the analyzer maps it
    # to a concrete method as needed.
    private def decode_chi_bind_call(call : LibTreeSitter::TSNode,
                                     source : String,
                                     prefix_stack : Array(String),
                                     local_groups : Hash(String, String),
                                     config : ScopedConfig,
                                     string_values : Hash(String, String) = Hash(String, String).new) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      operand = Noir::TreeSitter.field(function, "operand")
      return unless operand
      return unless Noir::TreeSitter.node_type(operand) == "identifier"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      raw_path = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          raw_path = decode_string_literal(arg, source) if raw_path.nil?
        else
          # A constant/variable first argument is still the bind path
          # (`s.BindHandler(rootPath, h)`); resolve it before falling
          # back to treating the arg as the handler.
          if raw_path.nil? && (resolved_path = string_expr_text(arg, source, string_values))
            raw_path = resolved_path
          elsif handler_text.empty? && !raw_path.nil?
            handler_text = Noir::TreeSitter.node_text(arg, source)
          end
        end
      end
      return unless raw_path

      router_name = Noir::TreeSitter.node_text(operand, source)
      return if NON_ROUTER_OPERANDS.includes?(router_name)
      base_prefix = local_groups[router_name]? || prefix_stack.join
      resolved = base_prefix.empty? ? raw_path : "#{base_prefix}#{raw_path}"

      Route.new(
        router_name,
        config.bind_method_verb,
        resolved,
        raw_path,
        handler_text,
        Noir::TreeSitter.node_start_row(call),
      )
    end

    # Resolve the verb-call receiver to a router name, rejecting known
    # non-router operands. Accepts a bare identifier (`r.Get(...)`) and
    # a struct-field selector (`s.router.Get(...)`), guarding the final
    # field of the selector against `NON_ROUTER_OPERANDS`. Returns nil
    # for any other operand shape (call chains, etc.).
    private def chi_router_operand_name(operand : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        name = Noir::TreeSitter.node_text(operand, source)
        return if NON_ROUTER_OPERANDS.includes?(name)
        name
      when "selector_expression"
        final_field = Noir::TreeSitter.field(operand, "field")
        return unless final_field
        return if NON_ROUTER_OPERANDS.includes?(Noir::TreeSitter.node_text(final_field, source))
        Noir::TreeSitter.node_text(operand, source)
      end
    end

    # Verb names a Combo chain may carry. `Combo` itself is chi's
    # `chi.Router#Combo`-less cousin from gitea's `modules/web` (and
    # macaron before it): `m.Combo("/path", mw...).Get(h).Post(h)`.
    COMBO_VERBS = Set{"Get", "Post", "Put", "Delete", "Patch", "Head", "Options"}

    # Decode `<router>.Combo("/path", ...).Get(h).Post(h)...` into one
    # Route per chained verb. `call` is the outermost (last) verb call.
    # Returns nil when the chain does not bottom out in a `Combo` call
    # so the caller can try the single-verb decoder instead. Each route
    # is attributed to the line its verb sits on, which for the usual
    # one-verb-per-line layout is the line a reader would point at.
    private def decode_chi_combo_chain(call : LibTreeSitter::TSNode,
                                       source : String,
                                       prefix_stack : Array(String),
                                       local_groups : Hash(String, String),
                                       string_values : Hash(String, String) = Hash(String, String).new) : Array(Route)?
      verbs = [] of Tuple(String, String, Int32)
      cursor = call
      loop do
        function = Noir::TreeSitter.field(cursor, "function")
        return unless function
        return unless Noir::TreeSitter.node_type(function) == "selector_expression"
        field = Noir::TreeSitter.field(function, "field")
        operand = Noir::TreeSitter.field(function, "operand")
        return unless field && operand
        name = Noir::TreeSitter.node_text(field, source)

        if name == "Combo"
          router_name = chi_router_operand_name(operand, source)
          return unless router_name
          raw_path = chi_first_string_arg(cursor, source, string_values)
          return unless raw_path
          return if verbs.empty?
          base_prefix = local_groups[router_name]? || prefix_stack.join
          resolved = base_prefix.empty? ? raw_path : "#{base_prefix}#{raw_path}"
          return verbs.reverse.map do |verb, handler_text, row|
            Route.new(router_name, verb, resolved, raw_path, handler_text, row)
          end
        end

        return unless COMBO_VERBS.includes?(name)
        verbs << {name.upcase, chi_last_arg_text(cursor, source), Noir::TreeSitter.node_start_row(field)}
        return unless Noir::TreeSitter.node_type(operand) == "call_expression"
        cursor = operand
      end
    end

    # Text of a call's last argument — the handler in gitea's
    # `Get(middleware..., handler)` convention.
    private def chi_last_arg_text(call : LibTreeSitter::TSNode, source : String) : String
      args = Noir::TreeSitter.field(call, "arguments")
      return "" unless args
      last = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        last = Noir::TreeSitter.node_text(arg, source)
      end
      last
    end

    # Decode `r.MethodFunc("GET", "/path", handler)` — chi's net/http
    # registration whose FIRST string arg is the HTTP method and second
    # is the route path. The method may be a custom verb registered via
    # `chi.RegisterMethod` (LINK/WOOHOO/...), so it is emitted verbatim.
    private def decode_chi_methodfunc_call(call : LibTreeSitter::TSNode,
                                           source : String,
                                           prefix_stack : Array(String),
                                           local_groups : Hash(String, String),
                                           string_values : Hash(String, String) = Hash(String, String).new) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      operand = Noir::TreeSitter.field(function, "operand")
      return unless operand
      router_name = chi_router_operand_name(operand, source)
      return unless router_name

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      method = nil
      raw_path = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        s = string_expr_text(arg, source, string_values)
        if method.nil?
          # First arg must be a string method ("GET", "WOOHOO", ...).
          return if s.nil?
          method = s
        elsif raw_path.nil?
          return if s.nil?
          raw_path = s
        elsif handler_text.empty?
          handler_text = Noir::TreeSitter.node_text(arg, source)
        end
      end
      return unless (m = method) && (path = raw_path)
      return unless path.starts_with?("/")
      return if handler_text.empty?

      base_prefix = local_groups[router_name]? || prefix_stack.join
      resolved = base_prefix.empty? ? path : group_join(base_prefix, path)
      Route.new(router_name, m.upcase, resolved, path, handler_text, Noir::TreeSitter.node_start_row(call))
    end

    # Decode `r.HandleFunc("/path", h)` / `r.Handle("/path", h)` — chi
    # registers these for EVERY HTTP method, so they are emitted with a
    # fan-out "ANY" verb (the analyzer expands it to each method).
    private def decode_chi_handle_all_call(call : LibTreeSitter::TSNode,
                                           source : String,
                                           prefix_stack : Array(String),
                                           local_groups : Hash(String, String),
                                           string_values : Hash(String, String) = Hash(String, String).new) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      operand = Noir::TreeSitter.field(function, "operand")
      return unless operand
      router_name = chi_router_operand_name(operand, source)
      return unless router_name

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      raw_path = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        s = string_expr_text(arg, source, string_values)
        if raw_path.nil?
          return if s.nil?
          raw_path = s
        elsif handler_text.empty?
          handler_text = Noir::TreeSitter.node_text(arg, source)
        end
      end
      return unless path = raw_path
      return unless path.starts_with?("/")
      return if handler_text.empty?

      base_prefix = local_groups[router_name]? || prefix_stack.join
      resolved = base_prefix.empty? ? path : group_join(base_prefix, path)
      Route.new(router_name, "ANY", resolved, path, handler_text, Noir::TreeSitter.node_start_row(call))
    end

    # Extract `{prefix, body_block, closure_node}` from a Route/Group call.
    # Returns nil if the call doesn't follow the expected shape. The
    # closure node is handed back so the caller can introspect its
    # parameter list (for binding the subrouter name into local_groups).
    private def unpack_chi_scope_call(call : LibTreeSitter::TSNode,
                                      source : String,
                                      string_values : Hash(String, String),
                                      expect_prefix : Bool) : Tuple(String, LibTreeSitter::TSNode, LibTreeSitter::TSNode)?
      prefix = expect_prefix ? chi_first_string_arg(call, source, string_values) : ""
      return if prefix.nil?
      closure = chi_closure_arg(call)
      return unless closure
      body = Noir::TreeSitter.field(closure, "body")
      return unless body
      {prefix, body, closure}
    end

    private def chi_first_string_arg(call : LibTreeSitter::TSNode,
                                     source : String,
                                     string_values : Hash(String, String) = Hash(String, String).new) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        # Resolve the first string-valued argument: a literal, or a
        # constant/variable/concatenation that `string_values` can pin
        # down (e.g. `const apiBase = "/api/v2"` used as `r.Route(apiBase,
        # ...)`). With an empty `string_values` map this still only
        # matches literals, preserving the original behaviour.
        if s = string_expr_text(arg, source, string_values)
          return s
        end
      end
      nil
    end

    private def chi_closure_arg(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        return arg if Noir::TreeSitter.node_type(arg) == "func_literal"
      end
      nil
    end

    # Decode a verb call that may sit at the end of a `.With(mw)...` chain,
    # optionally also peeling `.<prefix_method>("/x")` calls in the chain
    # so gf's `s.Group("/multi").GET("/line", ...)` resolves to
    # `/multi/line`.
    private def decode_chi_verb_call(call : LibTreeSitter::TSNode,
                                     source : String,
                                     prefix_stack : Array(String),
                                     local_groups : Hash(String, String),
                                     config : ScopedConfig,
                                     string_values : Hash(String, String) = Hash(String, String).new) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      verb_field = Noir::TreeSitter.field(function, "field")
      operand = Noir::TreeSitter.field(function, "operand")
      return unless verb_field && operand
      verb = Noir::TreeSitter.node_text(verb_field, source).upcase

      chain_prefix = ""

      # Peel passthrough chain. Chi uses `.With(mw)` / `.Use(mw)` which
      # don't change the prefix. Gf's chain `s.Group("/x").GET(...)`
      # accumulates the `/x` onto the route path.
      while Noir::TreeSitter.node_type(operand) == "call_expression"
        inner_fn = Noir::TreeSitter.field(operand, "function")
        break unless inner_fn
        break unless Noir::TreeSitter.node_type(inner_fn) == "selector_expression"
        inner_field = Noir::TreeSitter.field(inner_fn, "field")
        break unless inner_field
        inner_name = Noir::TreeSitter.node_text(inner_field, source)

        if inner_name == "With" || inner_name == "Use"
          next_op = Noir::TreeSitter.field(inner_fn, "operand")
          break unless next_op
          operand = next_op
          next
        end

        if config.chain_prefix? && inner_name == config.prefix_method
          # `.Group("/x")` in the chain must have a string arg and NO
          # func_literal (otherwise it'd already be handled as a Route
          # scope with its own closure body). Accumulate its prefix.
          inner_args = Noir::TreeSitter.field(operand, "arguments")
          break unless inner_args
          seen_closure = false
          prefix = nil
          Noir::TreeSitter.each_named_child(inner_args) do |arg|
            case Noir::TreeSitter.node_type(arg)
            when "interpreted_string_literal", "raw_string_literal"
              prefix ||= decode_string_literal(arg, source)
            when "func_literal"
              seen_closure = true
            end
          end
          break if seen_closure
          break unless prefix
          chain_prefix = "#{prefix}#{chain_prefix}"
          next_op = Noir::TreeSitter.field(inner_fn, "operand")
          break unless next_op
          operand = next_op
          next
        end

        break
      end

      # The verb receiver is usually a bare identifier (`r.Get(...)`), but
      # real apps just as often hang the router off a struct field
      # (`s.router.Get(...)`). Accept both; for the selector form, guard on
      # the final segment so non-router fields (`req.Header.Get(...)`,
      # `s.cache.Get(...)`) can't mint phantom routes.
      operand_is_selector = false
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        router_name = Noir::TreeSitter.node_text(operand, source)
        return if NON_ROUTER_OPERANDS.includes?(router_name)
      when "selector_expression"
        final_field = Noir::TreeSitter.field(operand, "field")
        return unless final_field
        return if NON_ROUTER_OPERANDS.includes?(Noir::TreeSitter.node_text(final_field, source))
        router_name = Noir::TreeSitter.node_text(operand, source)
        operand_is_selector = true
      else
        return
      end

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      raw_path = nil
      path_was_literal = false
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          if raw_path.nil?
            raw_path = decode_string_literal(arg, source)
            path_was_literal = true
          end
        else
          # Resolve a constant/variable/concatenation path argument
          # (`r.Get(tokenPath, h)`, `r.Post(adminPath+"/x", h)`) before
          # treating a non-string arg as the handler.
          if raw_path.nil? && (resolved_path = string_expr_text(arg, source, string_values))
            raw_path = resolved_path
          elsif handler_text.empty? && !raw_path.nil?
            handler_text = Noir::TreeSitter.node_text(arg, source)
          end
        end
      end
      return unless raw_path

      # A real chi/gf verb route's path is always rooted at `/`. Value
      # getters that share a verb name — gf's `genv.Get("GOPATH")`,
      # `r.Get("authorization")`, `gmeta.Get(req, "path")` — pass a bare
      # key, never a `/`-prefixed path, so this single guard drops them
      # without touching any genuine route (chi/gf both reject patterns
      # that don't start with `/`). Param-reads whose receiver is a call
      # chain (`r.URL.Query().Get("q")`) are already filtered by the
      # operand-type check above; this catches the bare-identifier
      # receivers (`genv`, `gmeta`, `r`) the operand check intentionally
      # allows through.
      #
      # The one exception is the empty path: chi itself panics on it,
      # but gitea's `modules/web` wrapper registers the group root as
      # `m.Get("", handler)` inside `m.Group("/secrets", func(){...})`.
      # It is accepted only when a group prefix is active and a handler
      # is present, so a value getter (`r.Get("")`) still cannot mint a
      # route.
      base_prefix = local_groups[router_name]? || prefix_stack.join
      unless raw_path.starts_with?("/")
        group_root = raw_path.empty? && path_was_literal &&
                     base_prefix.size > 0 && handler_text.size > 0
        return unless group_root
      end

      # Tighten the broadened cases (selector receiver or a path resolved
      # from a non-literal) so they can't surface noise: a real chi/gf
      # route always carries a handler. The original literal-path +
      # identifier-receiver shape keeps its historical leniency untouched.
      if operand_is_selector || !path_was_literal
        return if handler_text.empty?
      end

      # Prefer the local binding (closure param / `v1 := group.Group(...)`)
      # when it exists, since Go scope rules say the nearest binding wins.
      # Otherwise fall back to the ambient prefix stack.
      resolved = String.build do |io|
        io << base_prefix
        io << chain_prefix
        io << raw_path
      end

      Route.new(
        router_name,
        verb,
        resolved,
        raw_path,
        handler_text,
        Noir::TreeSitter.node_start_row(call),
      )
    end

    # ---- private helpers --------------------------------------------------
  end
end
