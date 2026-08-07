require "../../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter-backed Go route extractor.
  #
  # Scope for this first cut: recognise the idioms shared by Gin / Echo /
  # Fiber / Hertz / Iris — a router or group object with HTTP-verb methods
  # attached (`r.GET("/path", handler)`), plus `.Group("/prefix")`
  # chaining so nested groups resolve correctly.
  #
  # This file holds the shared route/group model, engine discovery and
  # the generic router-chain walker; the sibling files in this directory
  # reopen the module with one framework family's decoders each
  # (beego / chi / gf / go-zero / net/http / go-restful / statics).
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

    # The seven canonical HTTP methods Gin's `r.Any`, Echo's `e.Any`,
    # Beego's `*` route etc. all stand for. Used by analyzer-level
    # fan-out (see `fan_out_verbs`).
    ANY_FAN_OUT_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    # Returns the list of verbs to emit for a given extracted route
    # verb. `ANY` / `ALL` (case-insensitive — verbs are uppercased
    # before they reach this helper) expand to every canonical HTTP
    # method so downstream output formats list each method
    # explicitly instead of carrying a non-HTTP "ANY" verb that
    # tools like SARIF/Postman can't ingest. Anything else passes
    # through as a single-element list.
    def self.fan_out_verbs(verb : String) : Array(String)
      case verb.upcase
      when "ANY", "ALL"
        ANY_FAN_OUT_VERBS
      else
        [verb]
      end
    end

    # Common non-router identifiers in Go code that expose `.Get(string)`
    # or `.Post(...)` style methods but emit *values*, not routes. The
    # selector-expression walk emits a verb route on every match of
    # `<operand>.<HttpVerb>(stringLit, ...)`, so without this guard
    # patterns like `gjson.Get(json, "Files.0.UID")`,
    # `header.Get("Content-Type")`, or `params.Get("user")` become
    # bogus `/Files.0.UID`, `/Content-Type`, `/user` endpoints.
    #
    # Keep this list conservative — it only rejects names that are
    # almost never used to hold a real router instance. Generic names
    # like `r`, `c`, `app`, `mux`, `engine` are intentionally not
    # included.
    NON_ROUTER_OPERANDS = Set{
      "gjson", "result", "results",
      "header", "headers", "Header", "Headers",
      "cookie", "cookies", "Cookie", "Cookies",
      "params", "Params", "values", "Values",
      "vars", "Vars",
      "url", "URL", "uri", "URI",
      "cache", "Cache",
      "db", "DB", "tx", "Tx", "conn", "Conn",
      "config", "cfg", "conf", "Config",
      "logger", "log",
      "client", "Client",
      "request", "Request", "req", "Req",
      "response", "Response", "resp", "Resp",
      "fixtures", "Fixtures",
      # Go's structured-logging package exposes `slog.Any("key",
      # value)` (and `Group`, `Attr`, etc.) which the verb-decoder
      # would otherwise read as `Any /key`. Pocketbase parks
      # several `slog.Any("subscriptions", ...)` calls per file.
      "slog",
      # uber-go/zap — the most widely used structured logger in Go —
      # exposes the field constructor `zap.Any("key", value)`. Without
      # this guard `global.GVA_LOG.Info(..., zap.Any("error", err))`
      # surfaces as a phantom `Any /error` route fanned across all 7
      # HTTP verbs (observed in gin-vue-admin: `/error`, `/mode`).
      "zap",
      # The stdlib net/http package: `http.Handle("/x", h)` /
      # `http.HandleFunc("/x", h)` register on the default ServeMux and
      # collide with chi's identically-named all-methods registrations
      # (chi `net_http_methods` path). `http` is never a chi router, so
      # exclude it — otherwise every `http.Handle`/`http.HandleFunc` in a
      # chi app (promhttp metrics, pprof, …) fans out to 7 phantom verbs.
      # (`http.Get`/`http.Post` client calls are already dropped by the
      # scheme / handler-arg guards.)
      "http",
    }

    # Chain methods that return the receiving router/group unchanged —
    # middleware / metadata registration. Gin's `RouterGroup.Use(...)`
    # and `Engine.Use(...)` (and Fiber's `app.Use(...)`) return
    # `IRoutes`, so `r.Use(mw).GET("/x", h)` and
    # `r.Group("/api").Use(mw).POST(...)` are valid, common shapes.
    #
    # Goyave's router exposes a fluent builder whose configuration
    # methods (`SetMeta`, `Middleware`, `CORS`, ...) all return the same
    # `*Router`, so `authRouter := subrouter.Group().SetMeta(k, v)` binds
    # `authRouter` to the group's prefix — the `.SetMeta(...)` tail must
    # be peeled to reach the prefix-bearing `.Group()` call underneath
    # (otherwise the parent prefix is lost and every route under
    # `authRouter` falls back to `/`).
    #
    # None of these add a path segment, so the operand walk peels them
    # and resolves the prefix against the underlying router/group rather
    # than dropping the route (or its prefix) entirely.
    PASSTHROUGH_CHAIN_METHODS = Set{
      "Use",
      # Goyave fluent-builder configuration methods (all return *Router).
      "SetMeta", "RemoveMeta", "Middleware", "GlobalMiddleware", "CORS",
      # PocketBase's `*router.RouterGroup` middleware binders return the
      # group unchanged, so `sub := rg.Group("/x").Bind(mw)` /
      # `.Unbind(id)` must be peeled to reach the `.Group("/x")` prefix.
      # Without this the group var goes unresolved and falls back to a
      # cross-file binding of the same name — pocketbase reuses `subGroup`
      # across handler files, so one file's `/health` leaked onto every
      # other file's routes.
      "Bind", "Unbind", "BindFunc", "UnbindFunc",
    }

    # Beego registers controllers with `web.Router("/path", &Ctrl{},
    # "get:Method;post:Other")`. The receiver is the `web` package (v2,
    # `github.com/beego/beego/v2/server/web`) or the legacy `beego`
    # package alias (v1, `github.com/astaxie/beego`). Restricting the
    # operand to these two names keeps `something.Router(...)` calls on
    # unrelated types from minting phantom endpoints.
    BEEGO_ROUTER_OPERANDS = Set{"web", "beego"}

    # When a `web.Router` call carries no method-mapping string, Beego
    # auto-maps incoming requests to controller methods whose names match
    # an HTTP verb (Go-cased). Maps the receiver-method name to the HTTP
    # verb it serves so a mapping-less registration emits exactly the
    # methods the controller actually implements.
    BEEGO_CONTROLLER_HTTP_METHODS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
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
                       extra_verbs : Array(String) = [] of String,
                       handle_many_method : String? = nil,
                       closure_group_methods : Array(String) = [] of String) : Array(Route)
      routes = [] of Route
      group_prefixes = external_groups.dup
      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        mux_chained_operands = Set(String).new

        walk(root) do |node|
          next unless group_assignment_node?(node)
          collect_group(node, source, group_prefixes, group_method, group_aliases, string_values)
        end

        # Closure-scoped groups (Iris `Party("/x", func(p){...})` /
        # `PartyFunc("/x", func(p){...})`) — collected after the flat
        # group map so a closure receiver that is itself a package-level
        # group resolves correctly.
        closure_groups = closure_group_methods.empty? ? [] of ClosureGroup : collect_closure_groups(root, source, closure_group_methods, group_prefixes)

        if handlefunc_methods
          walk(root) do |node|
            next unless Noir::TreeSitter.node_type(node) == "call_expression"
            next unless mux_route_chain_call?(node, source)
            function = Noir::TreeSitter.field(node, "function")
            next unless function
            operand = Noir::TreeSitter.field(function, "operand")
            next unless operand
            next unless Noir::TreeSitter.node_type(operand) == "call_expression"
            mux_chained_operands << node_key(operand)
          end
        end

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if route = decode_verb_call(node, source, group_prefixes, extra_verbs, group_method, group_aliases, string_values, closure_groups)
            routes << route
          elsif handle_method && (route = decode_handle_call(node, source, group_prefixes, handle_method))
            routes << route
          elsif handle_many_method && (many = decode_handle_many_call(node, source, group_prefixes, handle_many_method)) && !many.empty?
            many.each { |r| routes << r }
          elsif handlefunc_methods && !mux_chained_operands.includes?(node_key(node))
            # Mux's `.Methods(...)` can list several verbs at once
            # (`.Methods("GET", "POST")`), so the decoder returns an
            # array and we fan out into one Route per verb.
            decode_handlefunc_methods_call(node, source, group_prefixes).each do |r|
              routes << r
            end
          end
        end
      end
      dedupe_routes(routes)
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
        string_values = collect_string_values(root, source)

        walk(root) do |node|
          next unless group_assignment_node?(node)
          collect_group(node, source, group_prefixes, group_method, group_aliases, string_values)
        end
      end
      group_prefixes
    end

    # A Gin "router-builder" helper — `func F(rg *gin.RouterGroup) {...}`
    # — whose body registers routes onto the passed-in group. `param` is
    # the group parameter's name; `start_row`/`end_row` bound the
    # declaration so the caller can suppress the (prefix-less) routes the
    # whole-file pass would otherwise emit for it.
    struct RouterBuilder
      getter param : String
      getter start_row : Int32
      getter end_row : Int32

      def initialize(@param, @start_row, @end_row)
      end
    end

    # Detects top-level Gin router-builder helpers. The canonical gin
    # project layout splits registration across `func addXRoutes(rg
    # *gin.RouterGroup)` helpers called from a central `getRoutes()` with
    # a versioned group (`addUserRoutes(router.Group("/v1"))`). The group
    # prefix lives at the call site, not in the helper, so the helper's
    # routes need that prefix grafted on (see `extract_routes_from_function`).
    # Returns `{func_name => RouterBuilder}`; only functions with exactly
    # one `*gin.RouterGroup` parameter qualify (an ambiguous count can't be
    # bound to a single prefix).
    def collect_router_group_builders(source : String) : Hash(String, RouterBuilder)
      result = Hash(String, RouterBuilder).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "function_declaration"
          name_node = Noir::TreeSitter.field(node, "name")
          params = Noir::TreeSitter.field(node, "parameters")
          next unless name_node && params
          param = router_group_param_name(params, source)
          next unless param
          result[Noir::TreeSitter.node_text(name_node, source)] =
            RouterBuilder.new(param, Noir::TreeSitter.node_start_row(node), Noir::TreeSitter.node_end_row(node))
        end
      end
      result
    end

    # Returns the sole `*gin.RouterGroup` parameter's name, or nil when
    # the function has zero or more than one such parameter.
    private def router_group_param_name(params : LibTreeSitter::TSNode, source : String) : String?
      found = nil
      count = 0
      Noir::TreeSitter.each_named_child(params) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "parameter_declaration"
        type_node = Noir::TreeSitter.field(decl, "type")
        name_node = Noir::TreeSitter.field(decl, "name")
        next unless type_node && name_node
        final = Noir::TreeSitter.node_text(type_node, source).lchop('*').split('.').last
        next unless final == "RouterGroup"
        count += 1
        found = Noir::TreeSitter.node_text(name_node, source)
      end
      count == 1 ? found : nil
    end

    # Finds calls to any of the named builder functions and returns
    # `[{func_name, first_arg_identifier}]`. The first argument names the
    # group passed in (`addUserRoutes(v1)` -> `{"addUserRoutes", "v1"}`),
    # which the caller resolves to a prefix via the package group map.
    def collect_router_builder_callsites(source : String, builders : Set(String)) : Array(Tuple(String, String))
      calls = [] of Tuple(String, String)
      return calls if builders.empty?
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          fn = Noir::TreeSitter.field(node, "function")
          next unless fn
          fn_name = Noir::TreeSitter.node_text(fn, source).split(".").last
          next unless builders.includes?(fn_name)
          name = fn_name
          args = Noir::TreeSitter.field(node, "arguments")
          next unless args
          first_arg = nil
          Noir::TreeSitter.each_named_child(args) { |a| first_arg ||= a }
          next unless first_arg
          arg_text = if Noir::TreeSitter.node_type(first_arg) == "identifier"
                       Noir::TreeSitter.node_text(first_arg, source)
                     elsif Noir::TreeSitter.node_type(first_arg) == "call_expression"
                       # Support inline `addX(router.Group("/v1"))` — treat the
                       # literal prefix as the "arg" key (resolve will see it
                       # starts with / and use directly).
                       gfn = Noir::TreeSitter.field(first_arg, "function")
                       if gfn && Noir::TreeSitter.node_text(gfn, source).split(".").last == "Group"
                         gargs = Noir::TreeSitter.field(first_arg, "arguments")
                         if gargs
                           lit = nil
                           Noir::TreeSitter.each_named_child(gargs) do |ga|
                             if s = string_expr_text(ga, source, {} of String => String)
                               if s.starts_with?("/")
                                 lit = s
                                 break
                               end
                             end
                           end
                           lit
                         end
                       end
                     end
          if arg_text
            calls << {name, arg_text}
          else
            # Non-identifier, non-inline-Group arg (e.g. expr, func result,
            # root router, etc.) — record so caller can apply "all sites must
            # resolve" guard and fall back to whole-file pass.
            calls << {name, "__unresolved__"}
          end
        end
      end
      calls
    end

    # Extracts the verb routes registered inside one named function's body,
    # seeding `external_groups` with the function's group parameter bound to
    # a call-site prefix (`{rg => "/v1"}`). This grafts the call-site prefix
    # onto routes a router-builder helper registers on its parameter group
    # (`users := rg.Group("/users"); users.GET("/")` -> `/v1/users/`). Route
    # line numbers stay relative to `source` so code paths remain accurate.
    def extract_routes_from_function(source : String, func_name : String,
                                     external_groups : Hash(String, String),
                                     handle_method : String? = nil) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        find_function_body_node(root, source, func_name) do |body|
          group_prefixes = external_groups.dup
          walk(body) do |node|
            next unless group_assignment_node?(node)
            collect_group(node, source, group_prefixes, "Group", [] of String, string_values)
          end
          walk(body) do |node|
            next unless Noir::TreeSitter.node_type(node) == "call_expression"
            if route = decode_verb_call(node, source, group_prefixes, [] of String, "Group", [] of String, string_values)
              routes << route
            elsif handle_method && (route = decode_handle_call(node, source, group_prefixes, handle_method))
              routes << route
            end
          end
        end
      end
      dedupe_routes(routes)
    end

    private def find_function_body_node(node : LibTreeSitter::TSNode, source : String, name : String, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "function_declaration"
        if (nn = Noir::TreeSitter.field(node, "name")) && Noir::TreeSitter.node_text(nn, source) == name
          if body = Noir::TreeSitter.field(node, "body")
            yield body
            return
          end
        end
      end
      Noir::TreeSitter.each_named_child(node) { |c| find_function_body_node(c, source, name, &block) }
    end

    # Collects Beego controller types and the HTTP-verb-named methods they
    # implement, keyed by the (package-unqualified) type name. Used to
    # resolve mapping-less `web.Router("/path", &Ctrl{})` registrations
    # into the concrete set of methods the controller serves. Built once
    # per package directory by the Beego analyzer (controllers and their
    # router registrations usually share a package).
    #
    # Only HTTP-verb method names are recorded — a `MainController` that
    # defines `Get`, `Health`, `Update` contributes `{"MainController" =>
    # ["Get"]}`, because Beego's default mapping only routes verb-named
    # methods; `Health`/`Update` are reachable solely via an explicit
    # `"get:Health"` mapping string.
    def extract_controller_methods(source : String) : Hash(String, Array(String))
      result = Hash(String, Array(String)).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "method_declaration"
          receiver = Noir::TreeSitter.field(node, "receiver")
          name_node = Noir::TreeSitter.field(node, "name")
          next unless receiver && name_node
          method_name = Noir::TreeSitter.node_text(name_node, source)
          next unless BEEGO_CONTROLLER_HTTP_METHODS.has_key?(method_name)
          type_name = receiver_type_name(receiver, source)
          next unless type_name
          list = (result[type_name] ||= [] of String)
          list << method_name unless list.includes?(method_name)
        end
      end
      result
    end

    # Framework constructors that mint a *root* router/engine — the
    # receiver they're assigned to carries no path prefix. A name bound
    # to one of these is the application root, never a sub-group.
    ENGINE_CONSTRUCTORS = Set{"New", "Default", "NewRouter"}

    # Engine/root type names (final identifier of the parameter type,
    # pointer stripped). A parameter of one of these types is the root
    # router handed in by the caller — `gin.Engine`, `echo.Echo`,
    # `fiber.App`, `chi.Mux`/`mux.Router` (the last shares `Router` with
    # group types, so it's intentionally omitted to avoid excluding
    # genuine group params).
    ENGINE_PARAM_TYPES = Set{"Engine", "Echo", "App", "Mux"}

    # Collects names that denote a *root* engine/router rather than a
    # path-bearing group:
    #
    #   r := gin.New()            / r := gin.Default()
    #   r := chi.NewRouter()      / e := echo.New()
    #   func setup(r *gin.Engine) / func setup(e *echo.Echo)
    #
    # The cross-file group pre-pass excludes these so a same-named local
    # group in a sibling file (e.g. `r := v1.Group("/sysjob")`) can't
    # leak a prefix onto the root and contaminate every route in the
    # package. Each file still resolves its own `r` locally during route
    # extraction; this only governs what crosses file boundaries.
    def extract_engine_names(source : String) : Set(String)
      names = Set(String).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "short_var_declaration", "assignment_statement", "var_spec"
            collect_engine_assignment(node, source, names)
          when "parameter_declaration"
            collect_engine_param(node, source, names)
          end
        end
      end
      names
    end

    # Single-parse combination of `extract_engine_names` +
    # `extract_groups` (with an empty external map). The Go engine's
    # group pre-pass needs BOTH per file — the root-engine names to
    # exclude from cross-file propagation and the file's own group
    # declarations — so folding them into one tree-sitter parse halves
    # the pre-pass parse count. Behaviour is identical to calling the two
    # extractors separately; only the parse is shared.
    def extract_engine_names_and_groups(source : String,
                                        group_method : String = "Group",
                                        group_aliases : Array(String) = [] of String) : Tuple(Set(String), Hash(String, String))
      names = Set(String).new
      group_prefixes = Hash(String, String).new
      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "short_var_declaration", "assignment_statement", "var_spec"
            collect_engine_assignment(node, source, names)
            collect_group(node, source, group_prefixes, group_method, group_aliases, string_values)
          when "parameter_declaration"
            collect_engine_param(node, source, names)
          end
        end
      end
      {names, group_prefixes}
    end

    # `<name> := <pkg>.New()` / `.Default()` / `.NewRouter()` → root name.
    private def collect_engine_assignment(node : LibTreeSitter::TSNode,
                                          source : String,
                                          names : Set(String))
      left = Noir::TreeSitter.field(node, "left")
      right = Noir::TreeSitter.field(node, "right")
      if Noir::TreeSitter.node_type(node) == "var_spec"
        left = Noir::TreeSitter.field(node, "name")
        right = Noir::TreeSitter.field(node, "value")
      end
      return unless left && right

      name_node = identifier_or_first_child(left)
      rhs_node = first_named_child(right)
      return unless name_node && rhs_node
      return unless Noir::TreeSitter.node_type(name_node) == "identifier"
      return unless Noir::TreeSitter.node_type(rhs_node) == "call_expression"

      function = Noir::TreeSitter.field(rhs_node, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless ENGINE_CONSTRUCTORS.includes?(Noir::TreeSitter.node_text(field, source))

      names << Noir::TreeSitter.node_text(name_node, source)
    end

    # `func f(<name> *gin.Engine)` / `(<name> *echo.Echo)` → root name.
    private def collect_engine_param(node : LibTreeSitter::TSNode,
                                     source : String,
                                     names : Set(String))
      name_node = Noir::TreeSitter.field(node, "name")
      type_node = Noir::TreeSitter.field(node, "type")
      return unless name_node && type_node
      return unless Noir::TreeSitter.node_type(name_node) == "identifier"

      type_text = Noir::TreeSitter.node_text(type_node, source)
      # Strip pointer / package qualifier: `*gin.Engine` -> `Engine`.
      final = type_text.lchop('*').split('.').last
      return unless ENGINE_PARAM_TYPES.includes?(final)

      names << Noir::TreeSitter.node_text(name_node, source)
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
      getter? net_http_methods : Bool

      def initialize(@prefix_method = "Route",
                     @middleware_method = "Group",
                     @chain_prefix = false,
                     @bind_methods = [] of String,
                     @bind_method_verb = "ALL",
                     @net_http_methods = false)
      end
    end

    # Collects `<name> := "literal"` / `const <name> = "literal"` string
    # bindings from `source`, keyed by name. Real chi/mux apps routinely
    # declare route paths as package constants
    # (`const tokenPath = "/api/v2/token"`) and register them with
    # `r.Get(tokenPath, h)`; the analyzer merges these per-package so the
    # scoped walker can resolve a constant/variable path argument to its
    # literal value. Conflicting redefinitions are dropped by
    # `collect_string_values`.
    def extract_string_values(source : String) : Hash(String, String)
      result = Hash(String, String).new
      Noir::TreeSitter.parse_go(source) do |root|
        result = collect_string_values(root, source)
      end
      result
    end

    # Gf-style: `.Group("/api", func(){...})` pushes prefix, inline
    # `s.Group("/multi").GET(...)` chain accumulates prefix onto the
    # next verb call, and `.BindHandler("/x", h)` registers a catch-all
    # route. Chi's default middleware `.Group(closure)` also works here
    # since the middleware arg-shape classifier is arg-based.
    # --- Static-file route extraction ------------------------------------

    private def extract_scoped_routes(source : String,
                                      config : ScopedConfig,
                                      skip_functions : Set(String) = Set(String).new,
                                      external_string_values : Hash(String, String) = Hash(String, String).new) : Array(Route)
      routes = [] of Route
      local_groups = Hash(String, String).new
      Noir::TreeSitter.parse_go(source) do |root|
        # Same-file string constants/vars win over package-level ones;
        # both feed the scoped walker so a `r.Get(tokenPath, h)` whose
        # path is a constant resolves to its literal value.
        string_values = external_string_values.dup
        collect_string_values(root, source).each { |k, v| string_values[k] = v }
        walk_chi(root, source, [] of String, local_groups, routes, skip_functions, config, string_values)
      end
      routes
    end

    # When the RHS is `<ident>.<prefix_method>("/path")` on a receiver
    # tracked in `local_groups`, add the new binding.
    private def bind_local_group(decl : LibTreeSitter::TSNode,
                                 source : String,
                                 local_groups : Hash(String, String),
                                 config : ScopedConfig,
                                 string_values : Hash(String, String) = Hash(String, String).new)
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

      path = chi_first_string_arg(rhs_node, source, string_values)
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
      MethodFunc
      HandleAll
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end

    private def node_key(node : LibTreeSitter::TSNode) : String
      "#{LibTreeSitter.ts_node_start_byte(node)}:#{LibTreeSitter.ts_node_end_byte(node)}"
    end

    private def mux_route_chain_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      function = Noir::TreeSitter.field(call, "function")
      return false unless function
      return false unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return false unless field

      case Noir::TreeSitter.node_text(field, source)
      when "Methods", "Queries", "HandleFunc", "Handle", "HandlerFunc", "Handler",
           "Path", "Host", "Schemes", "Headers", "HeadersRegexp", "Name",
           "MatcherFunc", "BuildOnly"
        true
      else
        false
      end
    end

    private def group_assignment_node?(node : LibTreeSitter::TSNode) : Bool
      case Noir::TreeSitter.node_type(node)
      when "short_var_declaration", "assignment_statement", "var_spec"
        true
      else
        false
      end
    end

    private def collect_string_values(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      values = Hash(String, String).new
      ambiguous = Set(String).new
      loop do
        changed = false
        walk(root) do |node|
          name_value = string_assignment(node, source, values)
          next unless name_value
          name, value = name_value
          next if ambiguous.includes?(name)
          if old_value = values[name]?
            next if old_value == value
            values.delete(name)
            ambiguous.add(name)
          else
            values[name] = value
          end
          changed = true
        end
        break unless changed
      end
      values
    end

    private def string_assignment(node : LibTreeSitter::TSNode,
                                  source : String,
                                  values : Hash(String, String)) : Tuple(String, String)?
      case Noir::TreeSitter.node_type(node)
      when "const_spec", "var_spec"
        name = Noir::TreeSitter.field(node, "name")
        value = Noir::TreeSitter.field(node, "value")
        return unless name && value
        return unless Noir::TreeSitter.node_type(name) == "identifier"
        expr = first_named_child(value)
        return unless expr
        text = string_expr_text(expr, source, values)
        return unless text
        {Noir::TreeSitter.node_text(name, source), text}
      else
        return unless group_assignment_node?(node)
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        name = first_named_child(left)
        expr = first_named_child(right)
        return unless name && expr
        return unless Noir::TreeSitter.node_type(name) == "identifier"
        text = string_expr_text(expr, source, values)
        return unless text
        {Noir::TreeSitter.node_text(name, source), text}
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
                              group_aliases : Array(String) = [] of String,
                              string_values : Hash(String, String) = Hash(String, String).new)
      left = Noir::TreeSitter.field(decl, "left")
      right = Noir::TreeSitter.field(decl, "right")
      if Noir::TreeSitter.node_type(decl) == "var_spec"
        left = Noir::TreeSitter.field(decl, "name")
        right = Noir::TreeSitter.field(decl, "value")
      end
      return unless left && right

      # `expression_list` wraps both sides; the single-variable case has
      # one named child on each side.
      var_name_node = identifier_or_first_child(left)
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

      # Peel trailing middleware pass-through calls so
      # `v1 := r.Group("/v1").Use(mw)` is recognised as a group
      # declaration for `v1` — the `.Use(...)` wraps the real
      # `.Group(...)` call without contributing a path segment.
      while PASSTHROUGH_CHAIN_METHODS.includes?(method_name) &&
            Noir::TreeSitter.node_type(parent_node) == "call_expression"
        inner_function = Noir::TreeSitter.field(parent_node, "function")
        break unless inner_function
        break unless Noir::TreeSitter.node_type(inner_function) == "selector_expression"
        inner_parent = Noir::TreeSitter.field(inner_function, "operand")
        inner_field = Noir::TreeSitter.field(inner_function, "field")
        break unless inner_parent && inner_field
        rhs_node = parent_node
        parent_node = inner_parent
        field_node = inner_field
        method_name = Noir::TreeSitter.node_text(field_node, source)
      end

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
                prefix = string_expr_text(arg, source, string_values)
                next unless prefix
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
        prefix = string_expr_text(arg, source, string_values)
        next unless prefix
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
                                 extra_verbs : Array(String) = [] of String,
                                 group_method : String = "Group",
                                 group_aliases : Array(String) = [] of String,
                                 string_values : Hash(String, String) = Hash(String, String).new,
                                 closure_groups : Array(ClosureGroup) = [] of ClosureGroup) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return unless operand && field

      verb = Noir::TreeSitter.node_text(field, source)
      return unless HTTP_VERB_METHODS.includes?(verb) || extra_verbs.includes?(verb)

      router_info = router_operand_info(operand, source, groups, group_method, group_aliases, string_values)
      return unless router_info
      router_name, chain_prefix = router_info
      # Reject known non-router operands so call shapes like
      # `gjson.Get(json, path)`, `header.Get("Content-Type")`, or
      # `params.Get("user")` don't surface as endpoints.
      return if NON_ROUTER_OPERANDS.includes?(router_name)

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      raw_path = nil
      handler_text = ""
      arg_index = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        if arg_index == 0
          # The route path must be the FIRST positional argument of a verb
          # call (`r.GET("/path", handler)` across Gin/Echo/Fiber/Beego/
          # Hertz/Iris). Bailing when arg0 isn't a string rejects
          # value-returning helpers that merely share a verb name — a
          # cache's `c.Put(ctx, "key", val)`, a store's `s.Get(ctx, "id")`,
          # etc. — whose first arg is a context/receiver, not a URL.
          # Previously the scan walked past the non-string first arg and
          # latched onto a later string literal, surfacing phantom routes
          # like `PUT /key` (observed across beego cache examples).
          raw_path = string_expr_text(arg, source, string_values)
        elsif handler_text.empty?
          # First non-string positional arg after the path is treated as
          # the handler — matches Gin/Echo/Fiber calling conventions.
          handler_text = Noir::TreeSitter.node_text(arg, source)
        end
        arg_index += 1
      end

      return unless raw_path

      # Filter out non-router method calls that masquerade as verb routes:
      #   * `http.Get("http://...")` — net/http client call. Real route
      #     paths are relative to the router and never carry a scheme.
      #   * `c.Get("clientChan")` — `gin.Context.Get` value lookup. Real
      #     route registrations always pass a handler argument after the
      #     path; the lookup helpers take a single string and nothing
      #     else.
      return if raw_path.includes?("://")
      return if handler_text.empty?

      # A closure-scoped group binding (Iris `PartyFunc("/x",
      # func(p){...})`) takes precedence over the flat group map: the
      # verb's receiver is the closure param, resolved by the innermost
      # enclosing closure body whose param matches.
      base_prefix = closure_prefix_for(closure_groups, LibTreeSitter.ts_node_start_byte(call), router_name) ||
                    groups[router_name]? || ""
      base_prefix = join_paths(base_prefix, chain_prefix) unless chain_prefix.empty?
      resolved = base_prefix.empty? ? (raw_path.empty? ? "/" : raw_path) : join_paths(base_prefix, raw_path)

      # Fiber's `app.All(...)` is the same "match any method" intent
      # as Gin's `r.Any(...)` and Echo's `e.Any(...)`. Normalize so
      # output is consistent across frameworks and the optimizer's
      # `allowed_methods` filter (which knows `ANY` but not `ALL`)
      # doesn't quietly demote it to GET.
      normalized_verb = verb.upcase == "ALL" ? "ANY" : verb.upcase

      Route.new(
        router_name,
        normalized_verb,
        resolved,
        raw_path,
        handler_text,
        Noir::TreeSitter.node_start_row(call),
      )
    end

    private def router_operand_info(operand : LibTreeSitter::TSNode,
                                    source : String,
                                    groups : Hash(String, String),
                                    group_method : String,
                                    group_aliases : Array(String),
                                    string_values : Hash(String, String)) : Tuple(String, String)?
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        {Noir::TreeSitter.node_text(operand, source), ""}
      when "call_expression"
        group_chain_operand_info(operand, source, groups, group_method, group_aliases, string_values)
      end
    end

    private def group_chain_operand_info(call : LibTreeSitter::TSNode,
                                         source : String,
                                         groups : Hash(String, String),
                                         group_method : String,
                                         group_aliases : Array(String),
                                         string_values : Hash(String, String)) : Tuple(String, String)?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      parent = Noir::TreeSitter.field(function, "operand")
      return unless field && parent

      method_name = Noir::TreeSitter.node_text(field, source)

      # Middleware pass-through (`.Use(...)`): the receiver is returned
      # unchanged, so skip this link and resolve the prefix against the
      # parent. Without this, a `r.Group("/x").Use(mw).GET(...)` chain
      # (the verb's operand is the `.Use(...)` call) would resolve to
      # nil and the route would be dropped.
      if PASSTHROUGH_CHAIN_METHODS.includes?(method_name)
        return router_operand_info(parent, source, groups, group_method, group_aliases, string_values)
      end

      return unless method_name == group_method || group_aliases.includes?(method_name)

      prefix = ""
      if method_name == group_method
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        Noir::TreeSitter.each_named_child(args) do |arg|
          prefix = string_expr_text(arg, source, string_values) || ""
          break unless prefix.empty?
        end
        return if prefix.empty?
      end

      parent_info = router_operand_info(parent, source, groups, group_method, group_aliases, string_values)
      return unless parent_info
      router_name, parent_prefix = parent_info
      chain_prefix = prefix.empty? ? parent_prefix : join_paths(parent_prefix, prefix)
      {router_name, chain_prefix}
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
        when "selector_expression"
          # The idiomatic constant form `router.Handle(http.MethodPut,
          # "/x", h)` — resolve via the shared http.MethodX helper.
          if method_lit.nil?
            candidate = decode_method_token(arg, source)
            method_lit = candidate unless candidate.empty?
          end
        else
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !path_lit.nil?
        end
      end

      return unless method_lit && path_lit
      return if method_lit.empty? || path_lit.empty?

      router_name = Noir::TreeSitter.node_text(operand, source)
      return if NON_ROUTER_OPERANDS.includes?(router_name)
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

    # Like `decode_handle_call` but the method argument lists several
    # verbs at once — Iris's `app.HandleMany("GET POST", "/x", h)` (and
    # the comma-separated `"GET,POST"` form). Fans out into one Route per
    # verb so each surfaces as its own endpoint.
    private def decode_handle_many_call(call : LibTreeSitter::TSNode,
                                        source : String,
                                        groups : Hash(String, String),
                                        handle_method : String) : Array(Route)
      empty = [] of Route
      function = Noir::TreeSitter.field(call, "function")
      return empty unless function
      return empty unless Noir::TreeSitter.node_type(function) == "selector_expression"
      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return empty unless operand && field
      return empty unless Noir::TreeSitter.node_type(operand) == "identifier"
      return empty unless Noir::TreeSitter.node_text(field, source) == handle_method

      args = Noir::TreeSitter.field(call, "arguments")
      return empty unless args

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
        when "selector_expression"
          # The idiomatic constant form `app.HandleMany(http.MethodGet,
          # "/x", h)` — resolve via the shared http.MethodX helper.
          if method_lit.nil?
            candidate = decode_method_token(arg, source)
            method_lit = candidate unless candidate.empty?
          end
        else
          handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !path_lit.nil?
        end
      end

      return empty unless method_lit && path_lit
      return empty if method_lit.empty? || path_lit.empty?

      router_name = Noir::TreeSitter.node_text(operand, source)
      return empty if NON_ROUTER_OPERANDS.includes?(router_name)
      resolved = if prefix = groups[router_name]?
                   join_paths(prefix, path_lit)
                 else
                   path_lit
                 end

      verbs = method_lit.split(/[\s,]+/).map(&.strip.upcase).reject(&.empty?)
      verbs.map do |verb|
        Route.new(router_name, verb, resolved, path_lit, handler_text,
          Noir::TreeSitter.node_start_row(call))
      end
    end

    # A closure-scoped route group: the inner routes are registered on
    # the closure's first parameter, with the prefix supplied to the
    # enclosing `Party`/`PartyFunc` call.
    private struct ClosureGroup
      getter start_byte : UInt32
      getter end_byte : UInt32
      getter param : String
      getter prefix : String

      def initialize(@start_byte, @end_byte, @param, @prefix)
      end
    end

    # Collect closure-scoped groups: `<recv>.<method>("/x", func(p
    # ...){...})`. Records each closure body's byte-range, its first
    # param name, and the resolved prefix. The receiver prefix is
    # resolved against the flat group map or an enclosing closure group
    # (so nested groups stack). Byte-range scoping keeps repeated param
    # names (`p`, `r`) from cross-contaminating — the inner-most body
    # containing a verb call wins — without touching the package-level
    # group map.
    private def collect_closure_groups(root : LibTreeSitter::TSNode,
                                       source : String,
                                       methods : Array(String),
                                       groups : Hash(String, String)) : Array(ClosureGroup)
      result = [] of ClosureGroup
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        function = Noir::TreeSitter.field(node, "function")
        next if function.nil?
        next unless Noir::TreeSitter.node_type(function) == "selector_expression"
        fld = Noir::TreeSitter.field(function, "field")
        next if fld.nil?
        next unless methods.includes?(Noir::TreeSitter.node_text(fld, source))

        args = Noir::TreeSitter.field(node, "arguments")
        next if args.nil?
        prefix_str = nil
        closure = nil
        Noir::TreeSitter.each_named_child(args) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "interpreted_string_literal", "raw_string_literal"
            prefix_str ||= decode_string_literal(arg, source)
          when "func_literal"
            closure ||= arg
          end
        end
        ps = prefix_str
        cl = closure
        next if ps.nil? || cl.nil?
        body = Noir::TreeSitter.field(cl, "body")
        next if body.nil?
        param = extract_closure_first_param_name(cl, source)
        next if param.nil?

        recv_prefix = ""
        recv = Noir::TreeSitter.field(function, "operand")
        if recv && Noir::TreeSitter.node_type(recv) == "identifier"
          rname = Noir::TreeSitter.node_text(recv, source)
          recv_prefix = groups[rname]? ||
                        closure_prefix_for(result, LibTreeSitter.ts_node_start_byte(node), rname) || ""
        end

        full = recv_prefix.empty? ? ps : join_paths(recv_prefix, ps)
        result << ClosureGroup.new(
          LibTreeSitter.ts_node_start_byte(body),
          LibTreeSitter.ts_node_end_byte(body),
          param,
          full,
        )
      end
      result
    end

    # Innermost closure-group prefix for a verb call at byte offset
    # `pos` whose receiver is `name` — the smallest body that both
    # contains `pos` and binds `name`. Returns nil when none match.
    private def closure_prefix_for(groups : Array(ClosureGroup), pos : UInt32, name : String) : String?
      best : ClosureGroup? = nil
      groups.each do |g|
        next unless g.param == name
        next unless pos >= g.start_byte && pos < g.end_byte
        if best.nil? || (g.end_byte - g.start_byte) < (best.end_byte - best.start_byte)
          best = g
        end
      end
      best.try &.prefix
    end

    # Decode mux route chains:
    #
    #   * `<router>.HandleFunc("/path", handler).Methods(...)`
    #   * `<router>.Handle("/path", handler).Methods(...)`
    #   * `<router>.Methods(...).Path("/path").HandlerFunc(handler)`
    #   * `<router>.Path("/path").Methods(...).Handler(handler)`
    #
    # Returns one Route per method listed, so `.Methods("GET", "POST")`
    # emits both endpoints. Further chained calls like `.Queries(...)`,
    # `.Name(...)`, `.Host(...)`, etc. are peeled back while collecting
    # route metadata.
    private def decode_handlefunc_methods_call(call : LibTreeSitter::TSNode,
                                               source : String,
                                               groups : Hash(String, String)) : Array(Route)
      empty = [] of Route

      current = call
      raw_path = nil
      handler_text = ""
      verbs = [] of String
      query_params = [] of String
      saw_registration = false
      saw_methods = false
      build_only = false
      registration_line = Noir::TreeSitter.node_start_row(call)
      router_name = nil

      loop do
        fn = Noir::TreeSitter.field(current, "function")
        return empty unless fn
        return empty unless Noir::TreeSitter.node_type(fn) == "selector_expression"
        fld = Noir::TreeSitter.field(fn, "field")
        return empty unless fld
        field_name = Noir::TreeSitter.node_text(fld, source)

        case field_name
        when "Methods"
          saw_methods = true
          if methods_args = Noir::TreeSitter.field(current, "arguments")
            Noir::TreeSitter.each_named_child(methods_args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                verbs << decode_string_literal(arg, source).upcase
              when "selector_expression"
                # The idiomatic constant form `.Methods(http.MethodGet,
                # http.MethodPut)` — `http.MethodPut` → "PUT". Without this
                # every constant-verb route silently fell back to GET.
                if verb = decode_method_token(arg, source)
                  verbs << verb unless verb.empty?
                end
              end
            end
          end
        when "Queries"
          if q_args = Noir::TreeSitter.field(current, "arguments")
            idx = 0
            Noir::TreeSitter.each_named_child(q_args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                query_params << decode_string_literal(arg, source) if idx.even?
                idx += 1
              end
            end
          end
        when "HandleFunc", "Handle"
          saw_registration = true
          registration_line = Noir::TreeSitter.node_start_row(current)
          if args = Noir::TreeSitter.field(current, "arguments")
            Noir::TreeSitter.each_named_child(args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                raw_path ||= decode_string_literal(arg, source)
              else
                handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty? && !raw_path.nil?
              end
            end
          end
        when "HandlerFunc", "Handler"
          saw_registration = true
          registration_line = Noir::TreeSitter.node_start_row(current)
          if args = Noir::TreeSitter.field(current, "arguments")
            Noir::TreeSitter.each_named_child(args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                # Handler/HandlerFunc don't carry a path in mux's builder
                # API, but ignore string args defensively.
              else
                handler_text = Noir::TreeSitter.node_text(arg, source) if handler_text.empty?
              end
            end
          end
        when "Path"
          if args = Noir::TreeSitter.field(current, "arguments")
            Noir::TreeSitter.each_named_child(args) do |arg|
              case Noir::TreeSitter.node_type(arg)
              when "interpreted_string_literal", "raw_string_literal"
                raw_path ||= decode_string_literal(arg, source)
                break
              end
            end
          end
        when "BuildOnly"
          # gorilla/mux guarantees a BuildOnly route never matches a real
          # request — it exists solely to reverse-build URLs elsewhere.
          # Suppress the whole chain rather than emit a phantom endpoint.
          build_only = true
        when "Host", "Schemes", "Headers", "HeadersRegexp", "Name", "MatcherFunc"
          # Metadata/matcher chain; keep peeling.
        else
          return empty
        end

        operand = Noir::TreeSitter.field(fn, "operand")
        return empty unless operand
        case Noir::TreeSitter.node_type(operand)
        when "identifier"
          router_name = Noir::TreeSitter.node_text(operand, source)
          break
        when "call_expression"
          current = operand
        else
          return empty
        end
      end

      return empty if build_only
      return empty unless router_name && raw_path && saw_registration
      return empty if handler_text.empty?
      verbs << (saw_methods ? "GET" : "ANY") if verbs.empty?

      return [] of Route if NON_ROUTER_OPERANDS.includes?(router_name)
      resolved = if prefix = groups[router_name]?
                   join_paths(prefix, raw_path)
                 else
                   raw_path
                 end

      verbs.uniq.map do |verb|
        Route.new(router_name, verb, resolved, raw_path, handler_text, registration_line, query_params.dup)
      end
    end

    private def dedupe_routes(routes : Array(Route)) : Array(Route)
      deduped = [] of Route
      seen = Set(String).new
      routes.each do |route|
        key = String.build do |io|
          io << route.line << '\0'
          io << route.verb << '\0'
          io << route.path << '\0'
          io << route.handler << '\0'
          route.query_params.each do |param|
            io << param << '\0'
          end
        end
        next if seen.includes?(key)
        seen << key
        deduped << route
      end
      deduped
    end

    # Return the first named child of `node`, or nil if there isn't one.
    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def identifier_or_first_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      return node if Noir::TreeSitter.node_type(node) == "identifier"
      first_named_child(node)
    end

    private def string_expr_text(node : LibTreeSitter::TSNode,
                                 source : String,
                                 values : Hash(String, String)) : String?
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        decode_string_literal(node, source)
      when "identifier"
        values[Noir::TreeSitter.node_text(node, source)]?
      when "binary_expression"
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_text = string_expr_text(left, source, values)
        right_text = string_expr_text(right, source, values)
        return unless left_text && right_text
        "#{left_text}#{right_text}"
      when "parenthesized_expression"
        child = first_named_child(node)
        child ? string_expr_text(child, source, values) : nil
      end
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
  end
end
