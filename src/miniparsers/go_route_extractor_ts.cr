require "../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter-backed Go route extractor.
  #
  # Scope for this first cut: recognise the idioms shared by Gin / Echo /
  # Fiber / Hertz / Iris — a router or group object with HTTP-verb methods
  # attached (`r.GET("/path", handler)`), plus `.Group("/prefix")`
  # chaining so nested groups resolve correctly.
  #
  # Deliberately not covered yet (legacy regex extractor still handles these):
  #   * Mux-style `r.HandleFunc("/x", h).Methods("GET")` chain
  #   * Chi's `r.Route("/api", func(r chi.Router) { ... })` nested closures
  #   * Static-file routes (`r.Static("/public", "./public")`)
  #
  # All of the above can grow into this extractor once the PoC is proven.
  module TreeSitterGoRouteExtractor
    extend self

    # HTTP verbs Gin/Echo/Fiber/etc. accept as method names on router
    # objects. Mixed case is allowed because both `r.GET(...)` (Gin) and
    # `r.Get(...)` (fiber, gin alt) appear in the wild.
    HTTP_VERB_METHODS = Set{
      "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
      "Get", "Post", "Put", "Delete", "Patch", "Head", "Options",
      "ANY", "Any", "All",
    }

    # A static-file route: URL `url_prefix` serves files from disk
    # location `disk_path`.
    struct StaticPath
      getter url_prefix : String
      getter disk_path : String
      getter line : Int32

      def initialize(@url_prefix, @disk_path, @line)
      end
    end

    struct Route
      getter router_name : String         # variable the verb is called on
      getter verb : String                # upper-cased verb
      getter path : String                # route path with group prefix applied
      getter raw_path : String            # path literal as written
      getter handler : String             # text of the handler argument (identifier or lambda snippet)
      getter line : Int32                 # 0-based line number of the call expression
      getter query_params : Array(String) # query-param constraints extracted from e.g. mux's `.Queries(...)`

      def initialize(@router_name, @verb, @path, @raw_path, @handler, @line,
                     @query_params : Array(String) = [] of String)
      end
    end

    # Parses `source` and returns every verb route it can resolve.
    # `external_groups` supplies group prefixes defined in other files of
    # the same Go package, so cross-file patterns like
    # `routes.go` calling `v1.GET(...)` under a `v1 := r.Group("/v1")`
    # declared in `main.go` resolve correctly.
    # `group_method` is the method name used for grouping — Gin/Echo/Fiber/
    # Hertz use `.Group(...)`, Iris uses `.Party(...)`. Mux uses the
    # special two-call chain `<parent>.PathPrefix("/prefix").Subrouter()`;
    # pass `"Subrouter"` and the collector will peek through the chain to
    # pull the prefix from the `.PathPrefix(...)` call.
    # `handle_method` is the "method-first" shape some routers use
    # (httprouter's `.Handle("METHOD", "/path", handler)`); set to nil
    # to disable.
    # `handlefunc_methods` enables mux's
    # `<router>.HandleFunc("/path", h).Methods("METHOD")` chain — the
    # outer call is `.Methods(...)`, so this piggybacks on the walk rather
    # than `decode_verb_call`.
    def extract_routes(source : String,
                       external_groups : Hash(String, String) = Hash(String, String).new,
                       group_method : String = "Group",
                       handle_method : String? = nil,
                       handlefunc_methods : Bool = false,
                       group_aliases : Array(String) = [] of String,
                       extra_verbs : Array(String) = [] of String) : Array(Route)
      routes = [] of Route
      group_prefixes = external_groups.dup
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "short_var_declaration"
          collect_group(node, source, group_prefixes, group_method, group_aliases)
        end

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if route = decode_verb_call(node, source, group_prefixes, extra_verbs)
            routes << route
          elsif handle_method && (route = decode_handle_call(node, source, group_prefixes, handle_method))
            routes << route
          elsif handlefunc_methods
            # Mux's `.Methods(...)` can list several verbs at once
            # (`.Methods("GET", "POST")`), so the decoder returns an
            # array and we fan out into one Route per verb.
            decode_handlefunc_methods_call(node, source, group_prefixes).each do |r|
              routes << r
            end
          end
        end
      end
      routes
    end

    # Extracts only `<name> := <parent>.<group_method>("/prefix")`
    # declarations. Used by the Go engine to run a cross-file fixpoint
    # so group names defined in one file but referenced in another are
    # known by the time `extract_routes` runs on the referencing file.
    def extract_groups(source : String,
                       external_groups : Hash(String, String) = Hash(String, String).new,
                       group_method : String = "Group",
                       group_aliases : Array(String) = [] of String) : Hash(String, String)
      group_prefixes = external_groups.dup
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "short_var_declaration"
          collect_group(node, source, group_prefixes, group_method, group_aliases)
        end
      end
      group_prefixes
    end

    # Chi-style extractor: walks the AST with a prefix stack so
    # `r.Route("/api", func(r chi.Router) { r.Get("/users", h) })`
    # resolves to `/api/users`. Handles arbitrarily-nested `.Route` blocks
    # plus `.Group(func(r){ body })` (middleware group, no prefix change)
    # and `r.With(mw).Get(...)` middleware chains (the verb receiver is
    # any chain of `.With(...)` calls that bottoms out at an identifier).
    #
    # `skip_functions` lets callers exclude function declarations whose
    # body is analysed separately — e.g. chi.cr's `analyze_router_function`
    # picks up `adminRouter()` under a `Mount("/admin", adminRouter())`,
    # so re-emitting the same routes from the free-floating function body
    # would duplicate them.
    # Config for the scope-aware walker. Chi and gf share the same
    # structural recognizer with different method names / extras.
    struct ScopedConfig
      getter prefix_method : String
      getter middleware_method : String?
      getter? chain_prefix : Bool
      getter bind_methods : Array(String)
      getter bind_method_verb : String

      def initialize(@prefix_method = "Route",
                     @middleware_method = "Group",
                     @chain_prefix = false,
                     @bind_methods = [] of String,
                     @bind_method_verb = "ALL")
      end
    end

    def extract_chi_routes(source : String,
                           skip_functions : Set(String) = Set(String).new) : Array(Route)
      extract_scoped_routes(source, ScopedConfig.new, skip_functions)
    end

    # Gf-style: `.Group("/api", func(){...})` pushes prefix, inline
    # `s.Group("/multi").GET(...)` chain accumulates prefix onto the
    # next verb call, and `.BindHandler("/x", h)` registers a catch-all
    # route. Chi's default middleware `.Group(closure)` also works here
    # since the middleware arg-shape classifier is arg-based.
    # --- Static-file route extraction ------------------------------------

    # `<router>.<method_name>("/prefix", "./dir", ...)`. The first two
    # string args are taken as `(url_prefix, disk_path)`. Covers the
    # Gin/Echo/Fiber/Hertz/GoZero shape.
    def extract_simple_statics(source : String, method_name : String = "Static") : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_simple_static(node, source, method_name)
            results << sp
          end
        end
      end
      results
    end

    # Goyave-style `<router>.Static(&fs, "/prefix", false)`: the first
    # `/`-prefixed string argument is the URL prefix; the disk path is
    # derived by stripping its leading slash (matching the legacy
    # extractor's behaviour, which used the same identifier for both).
    def extract_goyave_statics(source : String) : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_goyave_static(node, source)
            results << sp
          end
        end
      end
      results
    end

    # Mux-style `<router>.PathPrefix("/x/").Handler(<... http.Dir("./x/") ...>)`.
    # URL prefix comes from the `PathPrefix` arg; disk path from the
    # `http.Dir(...)` call nested somewhere inside the `Handler(...)`
    # argument expression.
    def extract_mux_statics(source : String) : Array(StaticPath)
      results = [] of StaticPath
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if sp = decode_mux_static(node, source)
            results << sp
          end
        end
      end
      results
    end

    def extract_gf_routes(source : String) : Array(Route)
      extract_scoped_routes(source, ScopedConfig.new(
        prefix_method: "Group",
        middleware_method: "Group",
        chain_prefix: true,
        bind_methods: ["BindHandler", "BindMiddleware"],
        bind_method_verb: "ALL",
      ))
    end

    private def extract_scoped_routes(source : String,
                                      config : ScopedConfig,
                                      skip_functions : Set(String) = Set(String).new) : Array(Route)
      routes = [] of Route
      local_groups = Hash(String, String).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk_chi(root, source, [] of String, local_groups, routes, skip_functions, config)
      end
      routes
    end

    # Exposes the closure-scoped walker against an arbitrary node
    # (typically a function body captured elsewhere). Uses chi defaults.
    def walk_chi_public(node : LibTreeSitter::TSNode,
                        source : String,
                        sink : Array(Route))
      local_groups = Hash(String, String).new
      skip = Set(String).new
      walk_chi(node, source, [] of String, local_groups, sink, skip, ScopedConfig.new)
    end

    private def walk_chi(node : LibTreeSitter::TSNode,
                         source : String,
                         prefix_stack : Array(String),
                         local_groups : Hash(String, String),
                         routes : Array(Route),
                         skip_functions : Set(String),
                         config : ScopedConfig)
      ty = Noir::TreeSitter.node_type(node)

      # Skip `func <skipped>() { ... }` bodies entirely — their routes are
      # emitted by a separate analysis pass (e.g. Mount expansion).
      if ty == "function_declaration" && !skip_functions.empty?
        if name_node = Noir::TreeSitter.field(node, "name")
          return if skip_functions.includes?(Noir::TreeSitter.node_text(name_node, source))
        end
      end

      # `v1 := group.Group("/v1")` inside a closure binds `v1` to the
      # combined prefix. We use `local_groups` instead of `prefix_stack`
      # here because the binding is name-scoped: sibling calls on the
      # outer receiver still refer to the outer prefix.
      if ty == "short_var_declaration"
        bind_local_group(node, source, local_groups, config)
      end

      if ty == "call_expression"
        kind = classify_chi_call(node, source, config)
        case kind
        when ChiCall::Route
          if info = unpack_chi_scope_call(node, source, expect_prefix: true)
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
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config)
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
          if info = unpack_chi_scope_call(node, source, expect_prefix: false)
            _, body, _ = info
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config)
            return
          end
        when ChiCall::Verb
          if route = decode_chi_verb_call(node, source, prefix_stack, local_groups, config)
            routes << route
          end
          return
        when ChiCall::Bind
          if route = decode_chi_bind_call(node, source, prefix_stack, local_groups, config)
            routes << route
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_chi(child, source, prefix_stack, local_groups, routes, skip_functions, config)
      end
    end

    # When the RHS is `<ident>.<prefix_method>("/path")` on a receiver
    # tracked in `local_groups`, add the new binding.
    private def bind_local_group(decl : LibTreeSitter::TSNode,
                                 source : String,
                                 local_groups : Hash(String, String),
                                 config : ScopedConfig)
      left = Noir::TreeSitter.field(decl, "left")
      right = Noir::TreeSitter.field(decl, "right")
      return unless left && right
      var_name_node = first_named_child(left)
      rhs_node = first_named_child(right)
      return unless var_name_node && rhs_node
      return unless Noir::TreeSitter.node_type(var_name_node) == "identifier"
      return unless Noir::TreeSitter.node_type(rhs_node) == "call_expression"

      function = Noir::TreeSitter.field(rhs_node, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      operand = Noir::TreeSitter.field(function, "operand")
      return unless field && operand
      return unless Noir::TreeSitter.node_type(operand) == "identifier"
      return unless Noir::TreeSitter.node_text(field, source) == config.prefix_method

      parent_name = Noir::TreeSitter.node_text(operand, source)
      parent_prefix = local_groups[parent_name]?
      return unless parent_prefix

      # Don't shadow when RHS has a closure arg — that's a new scope
      # already handled by the walker.
      return if chi_closure_arg(rhs_node)

      path = chi_first_string_arg(rhs_node, source)
      return unless path

      var_name = Noir::TreeSitter.node_text(var_name_node, source)
      local_groups[var_name] = "#{parent_prefix}#{path}"
    end

    private def extract_closure_first_param_name(closure : LibTreeSitter::TSNode, source : String) : String?
      params = Noir::TreeSitter.field(closure, "parameters")
      return unless params
      # `parameter_list` named children are `parameter_declaration`.
      Noir::TreeSitter.each_named_child(params) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "parameter_declaration"
        # Parameter names are named children of type `identifier`;
        # parameter types are separate fields.
        Noir::TreeSitter.each_named_child(decl) do |child|
          if Noir::TreeSitter.node_type(child) == "identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      nil
    end

    enum ChiCall
      None
      Route
      Group
      Verb
      Bind
    end

    # Classify a call_expression so `walk_chi` knows whether to descend
    # into a scoped body, emit a route, or keep walking children.
    private def classify_chi_call(call : LibTreeSitter::TSNode, source : String, config : ScopedConfig) : ChiCall
      function = Noir::TreeSitter.field(call, "function")
      return ChiCall::None unless function
      return ChiCall::None unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return ChiCall::None unless field
      name = Noir::TreeSitter.node_text(field, source)

      if name == config.prefix_method
        # (string, closure) -> push prefix. This also handles gf's
        # `.Group("/api", func(){...})`.
        if chi_first_string_arg(call, source) && chi_closure_arg(call)
          return ChiCall::Route
        end
      end

      if (mw = config.middleware_method) && name == mw
        # (closure only) -> middleware group that doesn't change prefix.
        # Excludes Gin-style `.Group("/x")` which is handled by
        # `extract_routes`, not this walker.
        if chi_closure_arg(call) && !chi_first_string_arg(call, source)
          return ChiCall::Group
        end
      end

      if config.bind_methods.includes?(name)
        return ChiCall::Bind
      end

      case name
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
           "Get", "Post", "Put", "Delete", "Patch", "Head", "Options"
        return ChiCall::Verb
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
                                     config : ScopedConfig) : Route?
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
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !raw_path.nil?
        end
      end
      return unless raw_path

      router_name = Noir::TreeSitter.node_text(operand, source)
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

    # Extract `{prefix, body_block, closure_node}` from a Route/Group call.
    # Returns nil if the call doesn't follow the expected shape. The
    # closure node is handed back so the caller can introspect its
    # parameter list (for binding the subrouter name into local_groups).
    private def unpack_chi_scope_call(call : LibTreeSitter::TSNode,
                                      source : String,
                                      expect_prefix : Bool) : Tuple(String, LibTreeSitter::TSNode, LibTreeSitter::TSNode)?
      prefix = expect_prefix ? chi_first_string_arg(call, source) : ""
      return if prefix.nil?
      closure = chi_closure_arg(call)
      return unless closure
      body = Noir::TreeSitter.field(closure, "body")
      return unless body
      {prefix, body, closure}
    end

    private def chi_first_string_arg(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          return decode_string_literal(arg, source)
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
                                     config : ScopedConfig) : Route?
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

      return unless Noir::TreeSitter.node_type(operand) == "identifier"
      router_name = Noir::TreeSitter.node_text(operand, source)

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      raw_path = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          raw_path = decode_string_literal(arg, source) if raw_path.nil?
        else
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !raw_path.nil?
        end
      end
      return unless raw_path

      # Prefer the local binding (closure param / `v1 := group.Group(...)`)
      # when it exists, since Go scope rules say the nearest binding wins.
      # Otherwise fall back to the ambient prefix stack.
      base_prefix = local_groups[router_name]? || prefix_stack.join
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

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end

    # Record `<name> := <parent>.Group("/prefix")`. Also accepts
    # `<name> = <parent>.Group(...)` (assignment) as a fallback, which
    # some codebases use for package-level groups. Resolves the prefix by
    # stacking onto `<parent>`'s prefix if it's already known.
    private def collect_group(decl : LibTreeSitter::TSNode,
                              source : String,
                              groups : Hash(String, String),
                              group_method : String,
                              group_aliases : Array(String) = [] of String)
      left = Noir::TreeSitter.field(decl, "left")
      right = Noir::TreeSitter.field(decl, "right")
      return unless left && right

      # `expression_list` wraps both sides; the single-variable case has
      # one named child on each side.
      var_name_node = first_named_child(left)
      rhs_node = first_named_child(right)
      return unless var_name_node && rhs_node
      return unless Noir::TreeSitter.node_type(var_name_node) == "identifier"
      return unless Noir::TreeSitter.node_type(rhs_node) == "call_expression"

      function = Noir::TreeSitter.field(rhs_node, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      parent_node = Noir::TreeSitter.field(function, "operand")
      field_node = Noir::TreeSitter.field(function, "field")
      return unless parent_node && field_node
      method_name = Noir::TreeSitter.node_text(field_node, source)

      # Goyave's zero-arg `v1 := api.Group()` is an "alias" declaration —
      # v1 inherits api's prefix without adding its own. We resolve these
      # immediately when the parent prefix is known.
      if group_aliases.includes?(method_name) && Noir::TreeSitter.node_type(parent_node) == "identifier"
        parent_name = Noir::TreeSitter.node_text(parent_node, source)
        if parent_prefix = groups[parent_name]?
          var_name = Noir::TreeSitter.node_text(var_name_node, source)
          groups[var_name] ||= parent_prefix
        end
        return
      end

      return unless method_name == group_method

      # Mux-style `api := r.PathPrefix("/api/").Subrouter()`: the outer
      # call is `.Subrouter()` with no arguments, and the prefix lives on
      # the inner `.PathPrefix("/api/")` call. Peel the chain one step
      # so the rest of this function sees "<parent>.PathPrefix(...)" as
      # the effective group-declaring call. Goyave's `.Subrouter("/api")`
      # takes the prefix as its own argument, which falls through to the
      # default path-extraction branch below.
      if group_method == "Subrouter" && Noir::TreeSitter.node_type(parent_node) == "call_expression"
        inner_function = Noir::TreeSitter.field(parent_node, "function")
        if inner_function && Noir::TreeSitter.node_type(inner_function) == "selector_expression"
          inner_field = Noir::TreeSitter.field(inner_function, "field")
          if inner_field && Noir::TreeSitter.node_text(inner_field, source) == "PathPrefix"
            inner_args = Noir::TreeSitter.field(parent_node, "arguments")
            if inner_args
              prefix = nil
              Noir::TreeSitter.each_named_child(inner_args) do |arg|
                next unless Noir::TreeSitter.node_type(arg) == "interpreted_string_literal"
                prefix = decode_string_literal(arg, source)
                break
              end
              return unless prefix
              new_parent = Noir::TreeSitter.field(inner_function, "operand")
              if new_parent && Noir::TreeSitter.node_type(new_parent) == "identifier"
                parent_name = Noir::TreeSitter.node_text(new_parent, source)
                if parent_prefix = groups[parent_name]?
                  prefix = join_paths(parent_prefix, prefix)
                end
              end
              groups[Noir::TreeSitter.node_text(var_name_node, source)] = prefix
              return
            end
          end
        end
        return
      end

      args = Noir::TreeSitter.field(rhs_node, "arguments")
      return unless args

      prefix = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "interpreted_string_literal"
        prefix = decode_string_literal(arg, source)
        break
      end
      return unless prefix

      # Stack onto parent group's prefix when it's known.
      if Noir::TreeSitter.node_type(parent_node) == "identifier"
        parent_name = Noir::TreeSitter.node_text(parent_node, source)
        if parent_prefix = groups[parent_name]?
          prefix = join_paths(parent_prefix, prefix)
        end
      end

      var_name = Noir::TreeSitter.node_text(var_name_node, source)
      groups[var_name] = prefix
    end

    # Decode `<router>.<VERB>("/path", <handler>...)`.
    private def decode_verb_call(call : LibTreeSitter::TSNode,
                                 source : String,
                                 groups : Hash(String, String),
                                 extra_verbs : Array(String) = [] of String) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return unless operand && field
      return unless Noir::TreeSitter.node_type(operand) == "identifier"

      verb = Noir::TreeSitter.node_text(field, source)
      return unless HTTP_VERB_METHODS.includes?(verb) || extra_verbs.includes?(verb)

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      raw_path = nil
      handler_text = ""
      index = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          if raw_path.nil?
            raw_path = decode_string_literal(arg, source)
          end
        else
          # First non-string positional arg after the path is treated as
          # the handler — matches Gin/Echo/Fiber calling conventions.
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !raw_path.nil?
        end
        index += 1
      end

      return unless raw_path

      router_name = Noir::TreeSitter.node_text(operand, source)
      resolved = if prefix = groups[router_name]?
                   join_paths(prefix, raw_path)
                 else
                   raw_path
                 end

      Route.new(
        router_name,
        verb.upcase,
        resolved,
        raw_path,
        handler_text,
        Noir::TreeSitter.node_start_row(call),
      )
    end

    # Decode `<router>.<handle_method>("METHOD", "/path", handler)` —
    # i.e. httprouter's `router.Handle("GET", "/x", h)`. Distinct from
    # `decode_verb_call` because the first positional argument is the
    # method, not the path. Returns nil when the shape doesn't match.
    private def decode_handle_call(call : LibTreeSitter::TSNode,
                                   source : String,
                                   groups : Hash(String, String),
                                   handle_method : String) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return unless operand && field
      return unless Noir::TreeSitter.node_type(operand) == "identifier"
      return unless Noir::TreeSitter.node_text(field, source) == handle_method

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      method_lit = nil
      path_lit = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          if method_lit.nil?
            method_lit = decode_string_literal(arg, source)
          elsif path_lit.nil?
            path_lit = decode_string_literal(arg, source)
          end
        else
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !path_lit.nil?
        end
      end

      return unless method_lit && path_lit
      return if method_lit.empty? || path_lit.empty?

      router_name = Noir::TreeSitter.node_text(operand, source)
      resolved = if prefix = groups[router_name]?
                   join_paths(prefix, path_lit)
                 else
                   path_lit
                 end

      Route.new(
        router_name,
        method_lit.upcase,
        resolved,
        path_lit,
        handler_text,
        Noir::TreeSitter.node_start_row(call),
      )
    end

    # Decode mux's `<router>.HandleFunc("/path", handler).Methods(...)`.
    # The outer call is `.Methods(...)` whose operand is the
    # `.HandleFunc(...)` call. Returns one Route per method listed, so
    # `.Methods("GET", "POST")` emits both endpoints. Further chained
    # calls like `.Queries(...)` wrap this one and are peeled back here
    # before looking at the operand.
    private def decode_handlefunc_methods_call(call : LibTreeSitter::TSNode,
                                               source : String,
                                               groups : Hash(String, String)) : Array(Route)
      empty = [] of Route

      # Walk back through any tail methods (`.Queries`, `.Host`, `.Schemes`)
      # stacked on top of `.Methods(...)` until we either find the
      # `.Methods(...)` call or give up. As we traverse, collect query-param
      # names from any `.Queries(...)` call — mux uses odd-positioned
      # strings as param names (`.Queries("type", "{type}", "page", "{page}")`
      # declares `type` and `page`).
      methods_call = call
      query_params = [] of String
      loop do
        fn = Noir::TreeSitter.field(methods_call, "function")
        return empty unless fn
        return empty unless Noir::TreeSitter.node_type(fn) == "selector_expression"
        fld = Noir::TreeSitter.field(fn, "field")
        return empty unless fld
        field_name = Noir::TreeSitter.node_text(fld, source)
        case field_name
        when "Methods"
          break
        when "Queries"
          if q_args = Noir::TreeSitter.field(methods_call, "arguments")
            idx = 0
            Noir::TreeSitter.each_named_child(q_args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                query_params << decode_string_literal(arg, source) if idx.even?
                idx += 1
              end
            end
          end
          next_call = Noir::TreeSitter.field(fn, "operand")
          return empty unless next_call
          return empty unless Noir::TreeSitter.node_type(next_call) == "call_expression"
          methods_call = next_call
        when "Host", "Schemes", "Headers", "HeadersRegexp"
          next_call = Noir::TreeSitter.field(fn, "operand")
          return empty unless next_call
          return empty unless Noir::TreeSitter.node_type(next_call) == "call_expression"
          methods_call = next_call
        else
          return empty
        end
      end

      function = Noir::TreeSitter.field(methods_call, "function")
      return empty unless function

      handlefunc_call = Noir::TreeSitter.field(function, "operand")
      return empty unless handlefunc_call
      return empty unless Noir::TreeSitter.node_type(handlefunc_call) == "call_expression"

      inner_function = Noir::TreeSitter.field(handlefunc_call, "function")
      return empty unless inner_function
      return empty unless Noir::TreeSitter.node_type(inner_function) == "selector_expression"

      router_node = Noir::TreeSitter.field(inner_function, "operand")
      inner_field = Noir::TreeSitter.field(inner_function, "field")
      return empty unless router_node && inner_field
      return empty unless Noir::TreeSitter.node_type(router_node) == "identifier"
      return empty unless Noir::TreeSitter.node_text(inner_field, source) == "HandleFunc"

      inner_args = Noir::TreeSitter.field(handlefunc_call, "arguments")
      return empty unless inner_args

      raw_path = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(inner_args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          if raw_path.nil?
            raw_path = decode_string_literal(arg, source)
          end
        else
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !raw_path.nil?
        end
      end
      return empty unless raw_path

      verbs = [] of String
      if methods_args = Noir::TreeSitter.field(methods_call, "arguments")
        Noir::TreeSitter.each_named_child(methods_args) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "interpreted_string_literal", "raw_string_literal"
            verbs << decode_string_literal(arg, source).upcase
          end
        end
      end
      verbs << "GET" if verbs.empty?

      router_name = Noir::TreeSitter.node_text(router_node, source)
      resolved = if prefix = groups[router_name]?
                   join_paths(prefix, raw_path)
                 else
                   raw_path
                 end

      line = Noir::TreeSitter.node_start_row(handlefunc_call)
      verbs.uniq.map do |verb|
        Route.new(router_name, verb, resolved, raw_path, handler_text, line, query_params.dup)
      end
    end

    # Return the first named child of `node`, or nil if there isn't one.
    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    # Decode a Go string literal node's text content. Interpreted
    # literals (`"foo"`) expose an `interpreted_string_literal_content`
    # named child; raw literals (`` `foo` ``) keep their contents as the
    # whole node text minus the backticks. We concatenate content children
    # for interpreted literals and strip backticks for raw literals.
    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal"
        buf = String.build do |io|
          Noir::TreeSitter.each_named_child(node) do |child|
            if Noir::TreeSitter.node_type(child) == "interpreted_string_literal_content"
              io << Noir::TreeSitter.node_text(child, source)
            end
          end
        end
        buf
      when "raw_string_literal"
        text = Noir::TreeSitter.node_text(node, source)
        text.starts_with?('`') && text.ends_with?('`') ? text[1..-2] : text
      else
        ""
      end
    end

    # Join a group prefix and a route path with exactly one `/` separator,
    # mirroring `GoRouteExtractor#extract_route_path`. Gin accepts paths
    # without a leading `/` under a group, so this also handles that case.
    private def join_paths(prefix : String, path : String) : String
      "#{prefix.rstrip('/')}/#{path.lstrip('/')}"
    end

    # Decode `<router>.<method_name>("/prefix", "./dir", ...)`. The legacy
    # path extractor also stripped leading `./` and collapsed repeated
    # slashes in the disk path; we reproduce that here to stay
    # byte-compatible with downstream `resolve_public_dirs` behaviour.
    private def decode_simple_static(call : LibTreeSitter::TSNode,
                                     source : String,
                                     method_name : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == method_name

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      strings = [] of String
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          strings << decode_string_literal(arg, source)
          break if strings.size >= 2
        end
      end
      return if strings.size < 2

      url_prefix = strings[0]
      disk_path = strings[1].gsub(%r{//+}, "/")
      StaticPath.new(url_prefix, disk_path, Noir::TreeSitter.node_start_row(call))
    end

    # Decode goyave-style `<router>.Static(&fs, "/prefix", false)` — the
    # prefix is a `/`-leading string positional arg anywhere in the list.
    # The legacy impl derived the disk path by stripping the leading
    # slash, so we do the same.
    private def decode_goyave_static(call : LibTreeSitter::TSNode,
                                     source : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == "Static"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      prefix = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          candidate = decode_string_literal(arg, source)
          if candidate.starts_with?('/')
            prefix = candidate
            break
          end
        end
      end
      return unless prefix
      StaticPath.new(prefix, prefix.lchop('/'), Noir::TreeSitter.node_start_row(call))
    end

    # Decode mux's `<router>.PathPrefix("/x/").Handler(... http.Dir("./x/") ...)`.
    # We recognise the outer `.Handler(...)` call whose operand is the
    # `.PathPrefix(...)` call, then walk the handler argument subtree to
    # find the nested `http.Dir(...)` for the disk path.
    private def decode_mux_static(call : LibTreeSitter::TSNode,
                                  source : String) : StaticPath?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      outer_field = Noir::TreeSitter.field(function, "field")
      return unless outer_field
      return unless Noir::TreeSitter.node_text(outer_field, source) == "Handler"

      pathprefix_call = Noir::TreeSitter.field(function, "operand")
      return unless pathprefix_call
      return unless Noir::TreeSitter.node_type(pathprefix_call) == "call_expression"

      pp_fn = Noir::TreeSitter.field(pathprefix_call, "function")
      return unless pp_fn
      return unless Noir::TreeSitter.node_type(pp_fn) == "selector_expression"
      pp_field = Noir::TreeSitter.field(pp_fn, "field")
      return unless pp_field
      return unless Noir::TreeSitter.node_text(pp_field, source) == "PathPrefix"

      pp_args = Noir::TreeSitter.field(pathprefix_call, "arguments")
      return unless pp_args
      url_prefix = nil
      Noir::TreeSitter.each_named_child(pp_args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "interpreted_string_literal", "raw_string_literal"
          url_prefix = decode_string_literal(arg, source)
          break
        end
      end
      return unless url_prefix

      handler_args = Noir::TreeSitter.field(call, "arguments")
      return unless handler_args

      disk_path = find_http_dir_arg(handler_args, source)
      return unless disk_path
      disk_path = disk_path.lchop("./")
      StaticPath.new(url_prefix, disk_path, Noir::TreeSitter.node_start_row(call))
    end

    # Recursively search `node` for a `http.Dir("...")` call and return
    # its first string argument. Used by the mux static decoder.
    private def find_http_dir_arg(node : LibTreeSitter::TSNode, source : String) : String?
      if Noir::TreeSitter.node_type(node) == "call_expression"
        if fn = Noir::TreeSitter.field(node, "function")
          if Noir::TreeSitter.node_type(fn) == "selector_expression"
            operand = Noir::TreeSitter.field(fn, "operand")
            fld = Noir::TreeSitter.field(fn, "field")
            if operand && fld &&
               Noir::TreeSitter.node_type(operand) == "identifier" &&
               Noir::TreeSitter.node_text(operand, source) == "http" &&
               Noir::TreeSitter.node_text(fld, source) == "Dir"
              if args = Noir::TreeSitter.field(node, "arguments")
                Noir::TreeSitter.each_named_child(args) do |arg|
                  case Noir::TreeSitter.node_type(arg)
                  when "interpreted_string_literal", "raw_string_literal"
                    return decode_string_literal(arg, source)
                  end
                end
              end
            end
          end
        end
      end

      result : String? = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        if found = find_http_dir_arg(child, source)
          result = found
          break
        end
      end
      result
    end
  end
end
