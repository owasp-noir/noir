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

    # GoFrame's standardized routing: a request struct embeds `g.Meta`
    # whose struct tag carries the route (`path:"/x" method:"get"`), and
    # `group.Bind(controller)` wires every such method up. The tag *is*
    # the route definition — it's exactly what gf's own OpenAPI generator
    # reads — so we surface it directly. `params` are the struct's own
    # request fields (json-tag name or field name); the analyzer types
    # them by HTTP method.
    struct GfMetaRoute
      getter path : String
      getter methods : Array(String)
      getter line : Int32
      getter params : Array(String)

      def initialize(@path, @methods, @line, @params)
      end
    end

    # go-restful (`github.com/emicklei/go-restful`) routes. Each WebService
    # declares a base `ws.Path("/users")` and registers routes as a nested
    # builder chain: `ws.Route(ws.GET("/{id}").To(h).Param(ws.PathParameter(
    # "id", ...)).Reads(User{}))`. The verb and sub-path live on the inner
    # `ws.GET(...)` call; the full path is the WebService's `Path()` prefix
    # joined with it; params are self-declared on the chain (`PathParameter`/
    # `QueryParameter`/`HeaderParameter`/`BodyParameter`/`FormParameter`) plus
    # `Reads(struct)` for the JSON body. `handler` carries the `.To(...)`
    # argument for callee wiring.
    struct RestfulRoute
      getter verb : String
      getter path : String
      getter handler : String
      getter line : Int32
      getter params : Array(Tuple(String, String)) # (name, in: path/query/header/json/form)

      def initialize(@verb, @path, @handler, @line, @params)
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

    # Extracts Beego controller-style routes:
    #
    #   web.Router("/health", ctrl, "get:Health")          -> GET /health
    #   web.Router("/x", c, "get,post:Handle")             -> GET /x, POST /x
    #   web.Router("/x", c, "get:Read;post:Write")         -> GET /x, POST /x
    #   web.Router("/any", c, "*:Any")                     -> ANY /any (fan-out)
    #   web.Router("/", &MainController{})                 -> verb routes
    #                                                         for each HTTP
    #                                                         method the
    #                                                         controller
    #                                                         implements
    #
    # `controller_methods` (see `extract_controller_methods`) supplies the
    # method set for the mapping-less form; when the controller type can't
    # be resolved (e.g. a cross-package `&controllers.User{}`), the route
    # falls back to a single GET so the endpoint is still surfaced rather
    # than dropped. The Route's `handler` carries the controller-method
    # name so the analyzer can attribute it as a callee.
    def extract_beego_routes(source : String,
                             controller_methods : Hash(String, Array(String)) = Hash(String, Array(String)).new) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        var_types = collect_controller_var_types(root, source)
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          decode_beego_router_call(node, source, controller_methods, var_types, string_values).each do |route|
            routes << route
          end
        end
      end
      dedupe_routes(routes)
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
        # Only `BindHandler` registers a request handler (a real
        # endpoint). `BindMiddleware`/`BindMiddlewareDefault` and
        # `BindHookHandler` attach middleware/hooks to a path *pattern*
        # (e.g. the catch-all `/*any`) — they are not endpoints, so
        # keeping them here minted phantom routes in every gf app.
        bind_methods: ["BindHandler"],
        bind_method_verb: "ALL",
      ))
    end

    # GoFrame standardized routing: scan every `type X struct { ... }`
    # for an embedded `g.Meta` field whose tag declares a route
    # (`path:"/x" method:"get"`). Each such struct is one endpoint (or
    # several, when `method` lists more than one verb). The struct's own
    # named fields become request params. This is method-/group-agnostic
    # on purpose: the tag fully specifies the route, the same way gf's
    # OpenAPI generator treats it, so we don't need to resolve the
    # `group.Bind(...)` site (whose prefix is often a runtime config
    # value we can't see statically).
    def extract_gf_meta_routes(source : String) : Array(GfMetaRoute)
      results = [] of GfMetaRoute
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "type_spec"
          type_node = Noir::TreeSitter.field(node, "type")
          next if type_node.nil?
          tn = type_node
          next unless Noir::TreeSitter.node_type(tn) == "struct_type"

          field_list = nil
          Noir::TreeSitter.each_named_child(tn) do |c|
            if Noir::TreeSitter.node_type(c) == "field_declaration_list"
              field_list = c
              break
            end
          end
          fl = field_list
          next if fl.nil?

          meta_tag = nil
          meta_line = Noir::TreeSitter.node_start_row(node)
          params = [] of String

          Noir::TreeSitter.each_named_child(fl) do |decl|
            next unless Noir::TreeSitter.node_type(decl) == "field_declaration"

            tag = ""
            if tag_node = Noir::TreeSitter.field(decl, "tag")
              tag = Noir::TreeSitter.node_text(tag_node, source).gsub(/^[`"]|[`"]$/, "")
            end

            if name_node = Noir::TreeSitter.field(decl, "name")
              # A genuine named request field — its json tag (or, lacking
              # one, the field name) is a request param.
              next if tag.includes?("path:") # defensive: not the meta line
              field_name = Noir::TreeSitter.node_text(name_node, source)
              pname = if m = tag.match(/json:"([^",]+)/)
                        m[1]
                      else
                        field_name
                      end
              params << pname unless pname.empty? || pname == "-"
            elsif type_node2 = Noir::TreeSitter.field(decl, "type")
              # Embedded field. The `g.Meta` carrier holds the route tag;
              # other embeds (`adminin.FooInp`) bring fields we can't see
              # cheaply, so they're skipped for params.
              embed_type = Noir::TreeSitter.node_text(type_node2, source)
              if (embed_type == "g.Meta" || embed_type.ends_with?(".Meta")) && tag.includes?("path:")
                meta_tag = tag
                meta_line = Noir::TreeSitter.node_start_row(decl)
              end
            end
          end

          mt = meta_tag
          next if mt.nil?
          path_match = mt.match(/path:"([^"]+)"/)
          next if path_match.nil?
          path = path_match[1]
          next unless path.starts_with?("/")

          methods = if mm = mt.match(/method:"([^"]+)"/)
                      mm[1].split(',').map(&.strip.upcase).reject(&.empty?)
                    else
                      [] of String
                    end
          # A method-less g.Meta route responds to ALL HTTP methods in
          # gf; represent that as "ALL" so the analyzer fans it out to
          # every canonical verb (rather than guessing a single one).
          methods = ["ALL"] if methods.empty?

          results << GfMetaRoute.new(path, methods, meta_line, params)
        end
      end
      results
    end

    RESTFUL_VERBS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    RESTFUL_PARAM_KINDS = {
      "PathParameter"   => "path",
      "QueryParameter"  => "query",
      "HeaderParameter" => "header",
      "BodyParameter"   => "json",
      "FormParameter"   => "form",
    }

    def extract_go_restful_routes(source : String) : Array(RestfulRoute)
      results = [] of RestfulRoute
      Noir::TreeSitter.parse_go(source) do |root|
        # Pass 1: map each WebService variable to its `Path("/prefix")`. The
        # call may be chained (`ws.Path("/x").Consumes(...).Produces(...)`),
        # but the `Path` selector's operand is still the bare ws identifier.
        prefixes = Hash(String, String).new
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          fn = Noir::TreeSitter.field(node, "function")
          next if fn.nil? || Noir::TreeSitter.node_type(fn) != "selector_expression"
          field = Noir::TreeSitter.field(fn, "field")
          next if field.nil? || Noir::TreeSitter.node_text(field, source) != "Path"
          operand = Noir::TreeSitter.field(fn, "operand")
          next if operand.nil? || Noir::TreeSitter.node_type(operand) != "identifier"
          if value = chi_first_string_arg(node, source)
            prefixes[Noir::TreeSitter.node_text(operand, source)] = value
          end
        end

        # Pass 2: every `<ws>.Route(<ws>.VERB("/sub")…)` registration.
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          fn = Noir::TreeSitter.field(node, "function")
          next if fn.nil? || Noir::TreeSitter.node_type(fn) != "selector_expression"
          field = Noir::TreeSitter.field(fn, "field")
          next if field.nil? || Noir::TreeSitter.node_text(field, source) != "Route"
          args = Noir::TreeSitter.field(node, "arguments")
          next if args.nil?
          builder = nil
          Noir::TreeSitter.each_named_child(args) do |arg|
            builder ||= arg if Noir::TreeSitter.node_type(arg) == "call_expression"
          end
          next if builder.nil?
          if route = decode_restful_builder(builder, source, prefixes, Noir::TreeSitter.node_start_row(node))
            results << route
          end
        end
      end
      results
    end

    # Peel a go-restful builder chain (`ws.GET("/x").To(h).Param(…).Reads(…)`)
    # from the outside in: the deepest call is the verb (`ws.GET("/x")`), the
    # intermediate `.Param(…)`/`.Reads(…)` calls carry the params, and the
    # verb's operand identifier selects the WebService `Path()` prefix.
    private def decode_restful_builder(builder : LibTreeSitter::TSNode,
                                       source : String,
                                       prefixes : Hash(String, String),
                                       line : Int32) : RestfulRoute?
      verb = nil
      sub_path = ""
      ws_var = nil
      handler = ""
      params = [] of Tuple(String, String)

      cur = builder
      while Noir::TreeSitter.node_type(cur) == "call_expression"
        call_fn = Noir::TreeSitter.field(cur, "function")
        break if call_fn.nil? || Noir::TreeSitter.node_type(call_fn) != "selector_expression"
        method_field = Noir::TreeSitter.field(call_fn, "field")
        break if method_field.nil?
        method_name = Noir::TreeSitter.node_text(method_field, source)

        if RESTFUL_VERBS.includes?(method_name)
          verb = method_name
          sub_path = chi_first_string_arg(cur, source) || ""
          operand = Noir::TreeSitter.field(call_fn, "operand")
          ws_var = Noir::TreeSitter.node_text(operand, source) if operand && Noir::TreeSitter.node_type(operand) == "identifier"
          break
        elsif method_name == "To"
          handler = restful_first_arg_text(cur, source) if handler.empty?
        elsif method_name == "Param"
          if p = decode_restful_param(cur, source)
            params << p
          end
        elsif method_name == "Reads"
          params << {"body", "json"} unless params.any? { |n, _| n == "body" }
        end

        operand = Noir::TreeSitter.field(call_fn, "operand")
        break if operand.nil?
        cur = operand
      end

      v = verb
      return if v.nil?

      # The chain is peeled outside-in, so params come out in reverse source
      # order — flip them back so they read as written.
      params.reverse!

      prefix = ws_var.try { |name| prefixes[name]? } || ""
      full = if sub_path.empty?
               # `ws.POST("")` registers the route at the WebService root —
               # the prefix itself, with no trailing slash.
               prefix.empty? ? "/" : prefix
             elsif prefix.empty?
               sub_path
             else
               join_paths(prefix, sub_path)
             end
      full = "/#{full}" unless full.starts_with?("/")
      RestfulRoute.new(v, full, handler, line, params)
    end

    # `ws.Param(ws.PathParameter("user-id", "desc")…)` — the arg is itself a
    # `ws.<Kind>Parameter("name", …)` builder; pull the kind and the name.
    private def decode_restful_param(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String)?
      args = Noir::TreeSitter.field(call, "arguments")
      return if args.nil?
      inner = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        inner ||= arg if Noir::TreeSitter.node_type(arg) == "call_expression"
      end
      # Peel an outer chain on the parameter builder
      # (`ws.PathParameter("id", "").DataType("integer")`) to its base call.
      node = inner
      while node && Noir::TreeSitter.node_type(node) == "call_expression"
        call_fn = Noir::TreeSitter.field(node, "function")
        break if call_fn.nil? || Noir::TreeSitter.node_type(call_fn) != "selector_expression"
        field = Noir::TreeSitter.field(call_fn, "field")
        break if field.nil?
        kind = Noir::TreeSitter.node_text(field, source)
        if param_in = RESTFUL_PARAM_KINDS[kind]?
          name = chi_first_string_arg(node, source)
          return if name.nil? || name.empty?
          return {name, param_in}
        end
        node = Noir::TreeSitter.field(call_fn, "operand")
      end
      nil
    end

    private def restful_first_arg_text(call : LibTreeSitter::TSNode, source : String) : String
      args = Noir::TreeSitter.field(call, "arguments")
      return "" if args.nil?
      Noir::TreeSitter.each_named_child(args) do |arg|
        return Noir::TreeSitter.node_text(arg, source)
      end
      ""
    end

    # go-zero registers routes as `rest.Route` struct literals rather than
    # verb calls, in two shapes:
    #
    #   server.AddRoutes(                       # generated routes.go
    #     []rest.Route{
    #       {Method: http.MethodPost, Path: "/user/login", Handler: h},
    #     },
    #     rest.WithPrefix("/usercenter/v1"),
    #   )
    #
    #   server.AddRoute(rest.Route{Method: http.MethodGet, Path: "/"})
    #   apiGroup := server.Group("/api/v1")     # hand-written grouping
    #   apiGroup.AddRoute(rest.Route{Path: "/products", ...})
    #
    # The verb/path live in the struct (not a `.Get(...)` call), and the
    # mount prefix comes from a trailing `rest.WithPrefix(...)` option
    # and/or a `server.Group("/p")` receiver — so the generic verb
    # extractor sees nothing. This decodes every route to its full mounted
    # path so it dedupes against the same route declared (prefix-applied)
    # in a `.api` file. `handler` carries the registered handler
    # expression for callee wiring.
    def extract_gozero_routes(source : String) : Array(Route)
      results = [] of Route
      Noir::TreeSitter.parse_go(source) do |root|
        group_prefixes = collect_gozero_group_prefixes(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          function = Noir::TreeSitter.field(node, "function")
          next if function.nil?
          next unless Noir::TreeSitter.node_type(function) == "selector_expression"
          fname_node = Noir::TreeSitter.field(function, "field")
          next if fname_node.nil?
          fname = Noir::TreeSitter.node_text(fname_node, source)
          next unless fname == "AddRoute" || fname == "AddRoutes"

          # The receiver may be the root server/engine (no prefix) or a
          # `:= server.Group("/p")` variable whose prefix we resolved.
          receiver = Noir::TreeSitter.field(function, "operand")
          base_prefix = ""
          if receiver && Noir::TreeSitter.node_type(receiver) == "identifier"
            base_prefix = group_prefixes[Noir::TreeSitter.node_text(receiver, source)]? || ""
          end

          args = Noir::TreeSitter.field(node, "arguments")
          next if args.nil?

          with_prefix = ""
          route_literal = nil
          Noir::TreeSitter.each_named_child(args) do |arg|
            case Noir::TreeSitter.node_type(arg)
            when "composite_literal"
              route_literal ||= arg
            when "call_expression"
              if p = gozero_with_prefix(arg, source)
                with_prefix = p
              end
            end
          end
          rl = route_literal
          next if rl.nil?

          prefix = "#{normalize_gozero_prefix(base_prefix)}#{normalize_gozero_prefix(with_prefix)}"

          # `[]rest.Route{...}` (slice) holds one struct per element;
          # `rest.Route{...}` (singular) is itself one route struct.
          type_node = Noir::TreeSitter.field(rl, "type")
          type_text = type_node ? Noir::TreeSitter.node_text(type_node, source) : ""
          body = Noir::TreeSitter.field(rl, "body")
          next if body.nil?

          if type_text.starts_with?("[]")
            Noir::TreeSitter.each_named_child(body) do |elem|
              inner = gozero_inner_value(elem)
              next if inner.nil?
              if route = gozero_decode_route_struct(inner, prefix, source, elem)
                results << route
              end
            end
          else
            if route = gozero_decode_route_struct(body, prefix, source, rl)
              results << route
            end
          end
        end
      end
      results
    end

    private def normalize_gozero_prefix(prefix : String) : String
      return "" if prefix.empty?
      prefix.starts_with?("/") ? prefix : "/#{prefix}"
    end

    # Decode a single `rest.Route{Method:..., Path:..., Handler:...}`
    # struct (given its `literal_value` body) into a Route, applying the
    # resolved mount prefix.
    private def gozero_decode_route_struct(inner : LibTreeSitter::TSNode, prefix : String,
                                           source : String, line_node : LibTreeSitter::TSNode) : Route?
      method = ""
      rpath = ""
      handler = ""
      Noir::TreeSitter.each_named_child(inner) do |kv|
        next unless Noir::TreeSitter.node_type(kv) == "keyed_element"
        key_node, val_node = gozero_keyed_pair(kv)
        next if key_node.nil? || val_node.nil?
        case Noir::TreeSitter.node_text(key_node, source)
        when "Method"  then method = decode_method_token(val_node, source)
        when "Path"    then rpath = gozero_string_value(val_node, source)
        when "Handler" then handler = Noir::TreeSitter.node_text(val_node, source)
        end
      end
      return if method.empty? || rpath.empty?
      return unless rpath.starts_with?("/")
      full = "#{prefix}#{rpath}"
      Route.new("server", method, full, rpath, handler, Noir::TreeSitter.node_start_row(line_node))
    end

    # Collect `groupVar := <recv>.Group("/p")` bindings, resolving nested
    # groups to their full prefix. The root receiver (`server`/`engine`)
    # contributes no prefix; a group-on-group accumulates. Iterated to a
    # fixpoint so `g2 := g1.Group("/x")` resolves regardless of source
    # order.
    private def collect_gozero_group_prefixes(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      prefixes = Hash(String, String).new
      10.times do
        changed = false
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "short_var_declaration"
          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          next if left.nil? || right.nil?
          var = first_named_child(left)
          rhs = first_named_child(right)
          next if var.nil? || rhs.nil?
          next unless Noir::TreeSitter.node_type(var) == "identifier"
          next unless Noir::TreeSitter.node_type(rhs) == "call_expression"
          func = Noir::TreeSitter.field(rhs, "function")
          next if func.nil? || Noir::TreeSitter.node_type(func) != "selector_expression"
          fld = Noir::TreeSitter.field(func, "field")
          next if fld.nil? || Noir::TreeSitter.node_text(fld, source) != "Group"
          recv = Noir::TreeSitter.field(func, "operand")
          next if recv.nil? || Noir::TreeSitter.node_type(recv) != "identifier"
          pstr = nil
          if rargs = Noir::TreeSitter.field(rhs, "arguments")
            Noir::TreeSitter.each_named_child(rargs) do |arg|
              s = gozero_string_value(arg, source)
              if pstr.nil? && !s.empty?
                pstr = s
              end
            end
          end
          next if pstr.nil?
          recv_name = Noir::TreeSitter.node_text(recv, source)
          base = (recv_name == "server" || recv_name == "engine") ? "" : (prefixes[recv_name]? || "")
          val = "#{base}#{normalize_gozero_prefix(pstr)}"
          vname = Noir::TreeSitter.node_text(var, source)
          if prefixes[vname]? != val
            prefixes[vname] = val
            changed = true
          end
        end
        break unless changed
      end
      prefixes
    end

    # Resolve a slice element to the `literal_value` holding its keyed
    # fields — transparent to a `literal_element` wrapper, an explicit
    # `rest.Route{...}` composite_literal, or a bare `{...}` literal_value.
    private def gozero_inner_value(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      n = node
      if Noir::TreeSitter.node_type(n) == "literal_element"
        fc = first_named_child(n)
        return if fc.nil?
        n = fc
      end
      case Noir::TreeSitter.node_type(n)
      when "literal_value"
        n
      when "composite_literal"
        Noir::TreeSitter.field(n, "body")
      end
    end

    # Unwrap a `literal_element` container (tree-sitter-go wraps both
    # sides of a keyed_element) to reach the underlying key/value node.
    private def gozero_unwrap(node : LibTreeSitter::TSNode?) : LibTreeSitter::TSNode?
      return if node.nil?
      if Noir::TreeSitter.node_type(node) == "literal_element"
        return first_named_child(node)
      end
      node
    end

    private def gozero_keyed_pair(kv : LibTreeSitter::TSNode) : Tuple(LibTreeSitter::TSNode?, LibTreeSitter::TSNode?)
      key = Noir::TreeSitter.field(kv, "key")
      val = Noir::TreeSitter.field(kv, "value")
      if key.nil? || val.nil?
        kids = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.each_named_child(kv) { |c| kids << c }
        return {nil, nil} if kids.size < 2
        key ||= kids[0]
        val ||= kids[1]
      end
      {gozero_unwrap(key), gozero_unwrap(val)}
    end

    # An HTTP method written as a string literal ("POST") or an
    # `http.MethodX` selector; both collapse to the bare upper-cased verb.
    # Shared by go-zero's `Method:` struct field and mux's `.Methods(...)`.
    private def decode_method_token(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        Noir::TreeSitter.node_text(node, source).gsub(/^["`]|["`]$/, "").upcase
      when "selector_expression"
        text = Noir::TreeSitter.node_text(node, source)
        if idx = text.index("Method")
          text[(idx + "Method".size)..].upcase
        else
          ""
        end
      else
        ""
      end
    end

    private def gozero_string_value(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        Noir::TreeSitter.node_text(node, source).gsub(/^["`]|["`]$/, "")
      else
        ""
      end
    end

    private def gozero_with_prefix(call : LibTreeSitter::TSNode, source : String) : String?
      function = Noir::TreeSitter.field(call, "function")
      return if function.nil?
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      fname = Noir::TreeSitter.field(function, "field")
      return if fname.nil?
      return unless Noir::TreeSitter.node_text(fname, source) == "WithPrefix"
      args = Noir::TreeSitter.field(call, "arguments")
      return if args.nil?
      Noir::TreeSitter.each_named_child(args) do |arg|
        s = gozero_string_value(arg, source)
        return s unless s.empty?
      end
      nil
    end

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

    # Exposes the closure-scoped walker against an arbitrary node
    # (typically a function body captured elsewhere). Uses chi defaults
    # incl. the net/http registrations (MethodFunc/HandleFunc/Handle) so a
    # Mount-expanded router function body is parsed like any chi file.
    def walk_chi_public(node : LibTreeSitter::TSNode,
                        source : String,
                        sink : Array(Route),
                        string_values : Hash(String, String) = Hash(String, String).new)
      local_groups = Hash(String, String).new
      skip = Set(String).new
      walk_chi(node, source, [] of String, local_groups, sink, skip, ScopedConfig.new(net_http_methods: true), string_values)
    end

    private def walk_chi(node : LibTreeSitter::TSNode,
                         source : String,
                         prefix_stack : Array(String),
                         local_groups : Hash(String, String),
                         routes : Array(Route),
                         skip_functions : Set(String),
                         config : ScopedConfig,
                         string_values : Hash(String, String) = Hash(String, String).new)
      ty = Noir::TreeSitter.node_type(node)

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
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config, string_values)
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
            walk_chi(body, source, prefix_stack, local_groups, routes, skip_functions, config, string_values)
            return
          end
        when ChiCall::Verb
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
        walk_chi(child, source, prefix_stack, local_groups, routes, skip_functions, config, string_values)
      end
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
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS",
           "Get", "Post", "Put", "Delete", "Patch", "Head", "Options"
        return ChiCall::Verb
      end

      if config.net_http_methods?
        # `r.MethodFunc("GET", "/x", h)` — method as the first string
        # arg (the route path is the second). Also covers custom verbs
        # registered via `chi.RegisterMethod`.
        return ChiCall::MethodFunc if name == "MethodFunc"
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
      resolved = base_prefix.empty? ? path : join_paths(base_prefix, path)
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
      resolved = base_prefix.empty? ? path : join_paths(base_prefix, path)
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
      return unless raw_path.starts_with?("/")

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
      resolved = base_prefix.empty? ? raw_path : join_paths(base_prefix, raw_path)

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
        when "Host", "Schemes", "Headers", "HeadersRegexp", "Name", "MatcherFunc", "BuildOnly"
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

    # Decode a single `web.Router(...)` / `beego.Router(...)` call into
    # zero or more routes (one per resolved HTTP method).
    private def decode_beego_router_call(call : LibTreeSitter::TSNode,
                                         source : String,
                                         controller_methods : Hash(String, Array(String)),
                                         var_types : Hash(String, String),
                                         string_values : Hash(String, String)) : Array(Route)
      empty = [] of Route
      function = Noir::TreeSitter.field(call, "function")
      return empty unless function
      return empty unless Noir::TreeSitter.node_type(function) == "selector_expression"
      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return empty unless operand && field
      return empty unless Noir::TreeSitter.node_type(operand) == "identifier"
      return empty unless BEEGO_ROUTER_OPERANDS.includes?(Noir::TreeSitter.node_text(operand, source))
      return empty unless Noir::TreeSitter.node_text(field, source) == "Router"

      args = Noir::TreeSitter.field(call, "arguments")
      return empty unless args

      path = nil
      controller_node : LibTreeSitter::TSNode? = nil
      mapping = nil
      idx = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        case idx
        when 0 then path = string_expr_text(arg, source, string_values)
        when 1 then controller_node = arg
        when 2 then mapping = string_expr_text(arg, source, string_values)
        end
        idx += 1
      end
      route_path = path
      return empty if route_path.nil? || route_path.empty?

      line = Noir::TreeSitter.node_start_row(call)
      ctrl_type = controller_node.try { |n| controller_type_name(n, source, var_types) }

      if mapping && !mapping.empty?
        parse_beego_mapping(mapping).map do |verb, fn|
          Route.new("web", verb, route_path, route_path, fn, line)
        end
      else
        methods = ctrl_type.try { |t| controller_methods[t]? }
        if methods && !methods.empty?
          # `compact_map` + `[m]?` is defensive: `controller_methods`
          # only carries HTTP-verb-named methods today, but a non-verb
          # name would otherwise raise on the direct lookup.
          methods.compact_map do |m|
            if verb = BEEGO_CONTROLLER_HTTP_METHODS[m]?
              Route.new("web", verb, route_path, route_path, m, line)
            end
          end
        else
          # Unresolved controller type: surface the endpoint under GET so
          # it isn't dropped entirely. Beego controllers almost always
          # implement `Get()`, so GET is the safest single-method guess.
          [Route.new("web", "GET", route_path, route_path, ctrl_type || "", line)]
        end
      end
    end

    # Parse a Beego method-mapping string into `{HTTP_VERB, func_name}`
    # pairs. Format: `"get:Method;post,put:Other"` — `;`-separated
    # segments, each `methods:funcname`, methods `,`-separated, `*`
    # meaning "any method".
    private def parse_beego_mapping(mapping : String) : Array(Tuple(String, String))
      result = [] of Tuple(String, String)
      mapping.split(';').each do |segment|
        segment = segment.strip
        next if segment.empty?
        colon = segment.index(':')
        next unless colon
        methods = segment[0...colon]
        fn = segment[(colon + 1)..].strip
        methods.split(',').each do |m|
          m = m.strip
          next if m.empty?
          result << ({m == "*" ? "ANY" : m.upcase, fn})
        end
      end
      result
    end

    # Scan the file for `name := &Ctrl{}` / `name := Ctrl{}` bindings so a
    # later `web.Router("/x", name)` can resolve `name`'s controller type.
    private def collect_controller_var_types(root : LibTreeSitter::TSNode,
                                             source : String) : Hash(String, String)
      var_types = Hash(String, String).new
      walk(root) do |node|
        next unless group_assignment_node?(node)
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        if Noir::TreeSitter.node_type(node) == "var_spec"
          left = Noir::TreeSitter.field(node, "name")
          right = Noir::TreeSitter.field(node, "value")
        end
        next unless left && right
        name_node = identifier_or_first_child(left)
        rhs = first_named_child(right)
        next unless name_node && rhs
        next unless Noir::TreeSitter.node_type(name_node) == "identifier"
        type_name = composite_literal_type_name(rhs, source)
        next unless type_name
        var_types[Noir::TreeSitter.node_text(name_node, source)] ||= type_name
      end
      var_types
    end

    # Resolve a controller argument node to its (unqualified) type name.
    # `identifier` → look up the var binding; anything wrapping a
    # `composite_literal` (`&Ctrl{}`, `Ctrl{}`) → the literal's type.
    private def controller_type_name(node : LibTreeSitter::TSNode,
                                     source : String,
                                     var_types : Hash(String, String)) : String?
      if Noir::TreeSitter.node_type(node) == "identifier"
        return var_types[Noir::TreeSitter.node_text(node, source)]?
      end
      composite_literal_type_name(node, source)
    end

    # Find a `composite_literal` at or under `node` and return its
    # (pointer-stripped) LOCAL type name. A package-qualified literal
    # (`&pkg.Ctrl{}`) returns nil: in Go a qualified type always lives in
    # another package, so its methods are never in this directory's
    # controller-method map. Returning nil routes such a route to the
    # unresolved-controller fallback instead of mis-matching a local type
    # that happens to share the final identifier (`Ctrl`).
    private def composite_literal_type_name(node : LibTreeSitter::TSNode,
                                            source : String) : String?
      comp = find_composite_literal(node)
      return unless comp
      type_node = Noir::TreeSitter.field(comp, "type") || first_named_child(comp)
      return unless type_node
      text = Noir::TreeSitter.node_text(type_node, source).lchop('*')
      return if text.includes?('.')
      text
    end

    private def find_composite_literal(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      return node if Noir::TreeSitter.node_type(node) == "composite_literal"
      result : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        if found = find_composite_literal(child)
          result = found
          break
        end
      end
      result
    end

    # Type name of a method receiver: `(c *MainController)` → `MainController`.
    private def receiver_type_name(receiver : LibTreeSitter::TSNode,
                                   source : String) : String?
      Noir::TreeSitter.each_named_child(receiver) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "parameter_declaration"
        type_node = Noir::TreeSitter.field(decl, "type")
        next unless type_node
        return final_type_identifier(type_node, source)
      end
      nil
    end

    # Strip a leading `*` (pointer) and any package qualifier, returning
    # the final identifier of a type expression: `*pkg.Foo` → `Foo`.
    private def final_type_identifier(type_node : LibTreeSitter::TSNode,
                                      source : String) : String
      Noir::TreeSitter.node_text(type_node, source).lchop('*').split('.').last
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

    # ---------------------------------------------------------------------
    # net/http (stdlib) support — dedicated, isolated from chi/mux/etc.
    # ---------------------------------------------------------------------

    # Local collection of net/http import aliases (supports default "http",
    # aliased `h "net/http"`, etc). Mirrors the logic in GoCalleeExtractor
    # but kept private here to avoid widening any public surface and to stay
    # isolated from other miniparsers.
    private def collect_http_aliases(source : String) : Set(String)
      aliases = Set(String).new
      Noir::TreeSitter.parse_go(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "import_spec"

          alias_name : String? = nil
          import_path : String? = nil
          Noir::TreeSitter.each_named_child(node) do |child|
            case Noir::TreeSitter.node_type(child)
            when "package_identifier"
              alias_name = Noir::TreeSitter.node_text(child, source)
            when "interpreted_string_literal", "raw_string_literal"
              txt = Noir::TreeSitter.node_text(child, source)
              import_path = unquote_like(txt)
            end
          end

          next unless path = import_path
          next unless path == "net/http"
          name = alias_name || "http"
          next if name.empty? || name == "_" || name == "."
          aliases << name
        end
      end
      if aliases.empty? && source.includes?("net/http")
        aliases << "http"
      end
      aliases
    end

    private def unquote_like(text : String) : String
      return text[1...-1] if text.size >= 2 && ((text.starts_with?("\"") && text.ends_with?("\"")) || (text.starts_with?("`") && text.ends_with?("`")))
      text
    end

    # Extracts routes registered directly against the Go standard library
    # `net/http` package (and its ServeMux). This covers the very common
    # bare-server pattern used in tutorials, internal tools and minimal
    # services:
    #
    #   http.HandleFunc("/hello", handler)
    #   http.Handle("/api", h)
    #
    #   mux := http.NewServeMux()
    #   mux.HandleFunc("/users", uh)
    #   mux.Handle("/old", oh)
    #
    #   // Go 1.22+ method-in-pattern form (verb is known at registration)
    #   mux.HandleFunc("POST /items", ih)
    #
    # The extractor ONLY returns registrations performed on:
    #   * the net/http package identifier (or alias: `import h "net/http"; h.HandleFunc`)
    #   * variables proven (via same-file assignment) to have originated from
    #     `http.NewServeMux()`, `&http.ServeMux{}`, or `http.ServeMux{}`
    #
    # This guarantees zero collision with chi's HandleFunc/Handle (which are
    # handled exclusively by the chi walker and would otherwise be mis-attributed
    # if we reused the generic mux handlefunc chain decoder).
    #
    # Routes are emitted with verb "ANY" (classic registrations match whatever
    # the handler decides at runtime) or the concrete verb when the modern
    # "METHOD /path" pattern form is used. Callers (the go_http analyzer) are
    # responsible for fanning ANY via `fan_out_verbs`.
    def extract_net_http_routes(source : String,
                                external_string_values : Hash(String, String) = Hash(String, String).new) : Array(Route)
      routes = [] of Route
      http_aliases = collect_http_aliases(source)
      return routes if http_aliases.empty?

      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        external_string_values.each { |k, v| string_values[k] ||= v }

        serve_mux_vars = collect_serve_mux_vars(root, source, http_aliases)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          if route = decode_net_http_registration(node, source, http_aliases, serve_mux_vars, string_values)
            routes << route
          end
        end
      end
      routes
    end

    # Collects names of local variables that are assigned a *http.ServeMux
    # (via NewServeMux or composite literal) inside this file. Only same-file
    # tracking is performed — cross-file ServeMux instances are out of scope
    # for the first cut (identical limitation to many other Go patterns).
    private def collect_serve_mux_vars(root : LibTreeSitter::TSNode,
                                       source : String,
                                       http_aliases : Set(String)) : Set(String)
      vars = Set(String).new
      walk(root) do |node|
        case Noir::TreeSitter.node_type(node)
        when "short_var_declaration", "assignment_statement", "var_spec"
          collect_serve_mux_assignment(node, source, http_aliases, vars)
        end
      end
      vars
    end

    private def collect_serve_mux_assignment(node : LibTreeSitter::TSNode,
                                             source : String,
                                             http_aliases : Set(String),
                                             vars : Set(String))
      left = Noir::TreeSitter.field(node, "left")
      right = Noir::TreeSitter.field(node, "right")
      if Noir::TreeSitter.node_type(node) == "var_spec"
        left = Noir::TreeSitter.field(node, "name")
        right = Noir::TreeSitter.field(node, "value")
      end
      return unless left && right

      name_nodes = [] of LibTreeSitter::TSNode
      if Noir::TreeSitter.node_type(left) == "identifier"
        name_nodes << left
      else
        Noir::TreeSitter.each_named_child(left) do |c|
          name_nodes << c if Noir::TreeSitter.node_type(c) == "identifier"
        end
      end
      return if name_nodes.empty?

      actual_rhs = right
      if Noir::TreeSitter.node_type(right) == "expression_list"
        actual_rhs = first_named_child(right) || right
      end
      if serve_mux_rhs?(actual_rhs, source, http_aliases)
        name_nodes.each do |n|
          vars << Noir::TreeSitter.node_text(n, source)
        end
      end
    end

    private def serve_mux_rhs?(node : LibTreeSitter::TSNode,
                               source : String,
                               http_aliases : Set(String)) : Bool
      actual = node
      if Noir::TreeSitter.node_type(node) == "expression_list"
        actual = first_named_child(node) || node
      end

      # http.NewServeMux() or alias.NewServeMux()
      if Noir::TreeSitter.node_type(actual) == "call_expression"
        if fn = Noir::TreeSitter.field(actual, "function")
          if Noir::TreeSitter.node_type(fn) == "selector_expression"
            operand = Noir::TreeSitter.field(fn, "operand")
            field = Noir::TreeSitter.field(fn, "field")
            if operand && field &&
               Noir::TreeSitter.node_type(operand) == "identifier" &&
               http_aliases.includes?(Noir::TreeSitter.node_text(operand, source)) &&
               Noir::TreeSitter.node_text(field, source) == "NewServeMux"
              return true
            end
          end
        end
      end

      # &http.ServeMux{}  or http.ServeMux{}  (or alias)
      txt = Noir::TreeSitter.node_text(actual, source)
      return true if http_aliases.any? { |a| txt.includes?("#{a}.ServeMux") }

      false
    end

    # Decodes a call that looks like `<recv>.HandleFunc("/p", h)` or
    # `<recv>.Handle("/p", h)` when recv is either a net/http alias or a
    # tracked serve-mux variable. Also peels one level of `NewServeMux().HandleFunc`
    # for the inline-creation pattern.
    private def decode_net_http_registration(call : LibTreeSitter::TSNode,
                                             source : String,
                                             http_aliases : Set(String),
                                             serve_mux_vars : Set(String),
                                             string_values : Hash(String, String)) : Route?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return unless operand && field

      method_name = Noir::TreeSitter.node_text(field, source)
      return unless method_name == "HandleFunc" || method_name == "Handle"

      router_name : String? = nil
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        name = Noir::TreeSitter.node_text(operand, source)
        if http_aliases.includes?(name)
          router_name = name
        elsif serve_mux_vars.includes?(name)
          router_name = name
        else
          return
        end
      when "call_expression"
        # http.NewServeMux().HandleFunc — the operand of the Handle* selector
        # is the NewServeMux() call itself. Accept only when the New call is on
        # a known http alias.
        if fn2 = Noir::TreeSitter.field(operand, "function")
          if Noir::TreeSitter.node_type(fn2) == "selector_expression"
            op2 = Noir::TreeSitter.field(fn2, "operand")
            fld2 = Noir::TreeSitter.field(fn2, "field")
            if op2 && fld2 &&
               Noir::TreeSitter.node_type(op2) == "identifier" &&
               http_aliases.includes?(Noir::TreeSitter.node_text(op2, source)) &&
               Noir::TreeSitter.node_text(fld2, source) == "NewServeMux"
              router_name = Noir::TreeSitter.node_text(op2, source)
            end
          end
        end
        return unless router_name
      else
        return
      end

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      raw_path : String? = nil
      handler_text = ""
      Noir::TreeSitter.each_named_child(args) do |arg|
        if raw_path.nil?
          if s = string_expr_text(arg, source, string_values)
            raw_path = s
          elsif Noir::TreeSitter.node_type(arg) == "interpreted_string_literal" || Noir::TreeSitter.node_type(arg) == "raw_string_literal"
            raw_path = decode_string_literal(arg, source)
          end
        elsif handler_text.empty?
          handler_text = Noir::TreeSitter.node_text(arg, source)
        end
      end

      return unless raw_path
      return if handler_text.empty?

      # Support Go 1.22+ "METHOD /path" registration pattern.
      # When present the verb is known statically; otherwise we emit ANY
      # (the analyzer fans it out to all methods, matching runtime behaviour).
      verb = "ANY"
      path = raw_path
      if m = raw_path.match(/^([A-Z]+)\s+(.*)$/i)
        candidate_verb = m[1].upcase
        candidate_path = m[2]
        if HTTP_VERB_METHODS.includes?(candidate_verb) || candidate_verb == "ANY" || candidate_verb == "ALL"
          verb = candidate_verb
          path = candidate_path
        end
      end

      return unless path.starts_with?("/")
      path = "/#{path}" unless path.starts_with?("/")
      path = normalize_net_http_pattern_path(path)

      Route.new(router_name, verb, path, raw_path, handler_text, Noir::TreeSitter.node_start_row(call))
    end

    # Go 1.22 ServeMux uses `{$}` as a special end-of-path wildcard.
    # `GET /{$}` matches exactly `/`, not a literal `/{ $ }` endpoint.
    private def normalize_net_http_pattern_path(path : String) : String
      return path unless path.ends_with?("{$}")

      normalized = path[0, path.size - "{$}".size]
      normalized.empty? ? "/" : normalized
    end
  end
end
