require "../../../models/analyzer"
require "../../../miniparsers/go_callee_extractor"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  private class ChiRouteState
    property prefix_stack : Array(String) = [] of String
    property? in_inline_handler : Bool = false
    property handler_brace_count : Int32 = 0
  end

  class Chi < Analyzer
    analyzer_for "go_chi"

    # Import path -> package directory, from the tree's go.mod files.
    @import_dirs = Hash(String, String).new
    # Per-file `{alias => import path}`, filled lazily for files that
    # mount a package-qualified router.
    @import_aliases_cache = Hash(String, Hash(String, String)).new
    # Per-directory string constants, shared with the Mount expansion.
    @package_string_values = Hash(String, Hash(String, String)).new

    # Go enforces per-file imports, so any file using chi's router
    # types must mention the package path. Filter on this marker
    # to avoid touching the bulk of files in projects whose
    # detection matched on a single dummy/fixture file (the chi
    # extractor is loose enough that another framework's verb
    # calls would otherwise surface as chi routes).
    IMPORT_MARKER = "github.com/go-chi/chi"

    # Whole-file gates, run on every `.go` in the tree.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)
    MOUNT_CALL_RE    = /\.Mount\(/

    def analyze
      result = [] of Endpoint

      # Pre-scan: collect per-directory file lists, mounted function names,
      # file contents, and TS-resolved route lists for each file.
      package_mounted_functions = Hash(String, Set(String)).new
      package_files = Hash(String, Array(String)).new
      file_contents_cache = Hash(String, String).new
      file_lines_cache = Hash(String, Array(String)).new
      # Directories that hold at least one chi-importing file. Route-path
      # constants (`const tokenPath = "/api/v2/token"`) are resolved only
      # for these so unrelated packages don't pay for an extra parse.
      chi_dirs = Set(String).new
      mount_files = [] of String
      # Files whose `.Mount(...)` lines resolve to a router the expander
      # can walk. They are visited even without the chi import marker:
      # gitea's `routers/init.go` mounts `apiv1.Routes()` through its own
      # `modules/web` wrapper and never names chi itself.
      expandable_mount_files = Set(String).new

      get_files_by_extension(".go").each do |scan_path|
        dir = File.dirname(scan_path)
        package_files[dir] ||= [] of String
        package_files[dir] << scan_path

        content = read_file_content(scan_path)
        chi_dirs << dir if content_matches?(content, IMPORT_MARKER_RE)
        # Cache contents for every Go file in the package — the
        # cross-file callee map and Mount-expansion walker both
        # need handler/helper functions that live in non-chi
        # source files (`handlers.go`, `helpers.go`). The
        # IMPORT_MARKER gate fires later, in the per-file route
        # extraction loop, where the savings actually matter.
        file_contents_cache[scan_path] = content
        file_lines_cache[scan_path] = content.lines

        # Mount targets are resolved after this loop (see below): the
        # target of `r.Mount("/api/v1", apiv1.Routes())` may live in a
        # package that has not been read yet.
        mount_files << scan_path if content_matches?(content, MOUNT_CALL_RE)
      rescue IO::Error
        # skip
      end

      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      # Chi extends `Analyzer` directly (not `GoEngine`), so we use the
      # module-level twins on `GoCalleeExtractor` instead of the engine
      # instance methods. Mount-expanded routes don't pick up callees
      # in this first cut — `analyze_router_function` runs its own
      # isolated route walk and would need separate wiring. Tracking
      # that as a follow-up; for now Mount endpoints keep an empty
      # callees list.
      package_function_bodies = Noir::GoCalleeExtractor.package_function_bodies_if(callees_needed?, file_contents_cache)
      # Method-value handlers (`s.handleOIDCRedirect`, `router.Get(p,
      # h.Show)`) resolve to their method bodies so callees aren't empty
      # when chi apps hang handlers off a server/controller struct.
      package_method_bodies = Noir::GoCalleeExtractor.package_method_bodies_if(callees_needed?, file_contents_cache)

      # Per-directory string-constant map so a route registered in one
      # file (`server.go`: `r.Get(tokenPath, h)`) resolves a path
      # constant declared in a sibling file (`httpd.go`:
      # `const tokenPath = "/api/v2/token"`). Conflicting redefinitions
      # across files are dropped so an ambiguous name never resolves to
      # the wrong path.
      package_string_values = Hash(String, Hash(String, String)).new
      chi_dirs.each do |dir|
        next unless files = package_files[dir]?
        merged = Hash(String, String).new
        ambiguous = Set(String).new
        files.each do |fp|
          content = file_contents_cache[fp]?
          next unless content
          Noir::TreeSitterGoRouteExtractor.extract_string_values(content).each do |name, value|
            next if ambiguous.includes?(name)
            if (existing = merged[name]?) && existing != value
              merged.delete(name)
              ambiguous << name
            else
              merged[name] = value
            end
          end
        end
        package_string_values[dir] = merged unless merged.empty?
      end
      @package_string_values = package_string_values

      # Import-path -> directory index for every package in the tree, so
      # a Mount target qualified by a package alias resolves to the
      # directory that declares it. Built once; gitea-style apps mount
      # a handful of routers from `routers/init.go` whose bodies live in
      # `routers/api/v1`, `routers/web`, `routers/private`, ...
      modules = collect_go_modules
      package_files.each_key do |dir|
        next if modules.empty?
        if import_path = import_path_for_dir(dir, modules)
          @import_dirs[import_path] = dir
        end
      end

      # Mount targets need a regex sweep — the name that appears in
      # `r.Mount("/admin", adminRouter())` is a *symbol*, not a route,
      # and it determines which function bodies to exclude from the
      # free-floating TS extraction pass below. The target may be a
      # plain function (`adminRouter()`), a struct value-method
      # (`todosResource{}.Routes()`) or a function in another package
      # (`apiv1.Routes()`); each contributes a *skip key* to the
      # directory that declares it (qualified by receiver type for
      # methods, so a same-named `Routes()` on another type — or a
      # top-level router builder also named `Routes()` — is not skipped
      # by accident). A target that cannot be resolved contributes
      # nothing: its routes then keep surfacing through the free pass,
      # unprefixed, exactly as before.
      mount_files.each do |scan_path|
        content = file_contents_cache[scan_path]? || next
        dir = File.dirname(scan_path)
        content.each_line do |scan_line|
          next unless scan_line.includes?(".Mount(")
          target = parse_mount_target(scan_line, string_values_for(dir))
          next unless target
          target_dir = resolve_mount_dir(scan_path, dir, target, file_contents_cache)
          next unless target_dir
          expandable_mount_files << scan_path
          package_mounted_functions[target_dir] ||= Set(String).new
          package_mounted_functions[target_dir] << mount_skip_key(target)
        end
      end

      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
        content = file_contents_cache[path]? || read_file_content(path)
        # A file without the chi import marker takes part only through
        # its resolvable `.Mount(...)` lines: the free-floating route
        # pass below stays gated on the marker so another framework's
        # verb calls cannot surface as chi routes.
        chi_file = content_matches?(content, IMPORT_MARKER_RE)
        next unless chi_file || expandable_mount_files.includes?(path)
        lines = file_lines_cache[path]? || content.lines

        dir = File.dirname(path)
        mounted_functions = package_mounted_functions.fetch(dir, Set(String).new)

        # Tree-sitter pre-pass: every `r.Get(...)` / `r.Route(...)`
        # / `r.Group(...)` resolved with the correct prefix, skipping
        # bodies of functions that are expanded via Mount (those
        # are handled below to get their `/admin` prefix).
        ts_routes = if chi_file
                      Noir::TreeSitterGoRouteExtractor
                        .extract_chi_routes(content, mounted_functions,
                          package_string_values[dir]? || Hash(String, String).new)
                    else
                      [] of Noir::TreeSitterGoRouteExtractor::Route
                    end
        routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
        ts_routes.each do |r|
          routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
          routes_by_line[r.line] << r
        end

        # Resolve 1-hop callees for every route in this file.
        # Inline-closure handlers (the common Chi shape inside
        # `r.Route("/x", func(r chi.Router){ r.Get(...) })`)
        # walk in place; bare identifier handlers fall through
        # to sibling-file function bodies via the per-directory map.
        route_rows = Set(Int32).new
        routes_by_line.each_key { |row| route_rows << row }
        external_fns = Noir::GoCalleeExtractor.function_bodies_for_directory(package_function_bodies, dir)
        external_methods = Noir::GoCalleeExtractor.method_bodies_for_directory(package_method_bodies, dir)
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)

        state = ChiRouteState.new
        last_endpoint = Endpoint.new("", "")
        in_mounted_func = false
        mounted_func_brace_count = 0

        lines.each_with_index do |line, index|
          # Skip bodies of mounted router functions so parameter
          # extraction only attributes them to the Mount-expanded
          # endpoints, not the free-floating verb calls we now
          # skip in the TS pass.
          if in_mounted_func
            mounted_func_brace_count += line.count("{")
            mounted_func_brace_count -= line.count("}")
            if mounted_func_brace_count <= 0
              in_mounted_func = false
            end
            next
          end
          if !mounted_functions.empty? && line.strip.starts_with?("func ")
            # Match both plain functions (`func adminRouter(`) and
            # methods (`func (rs todosResource) Routes(`); either
            # can be a mount target whose body must be skipped so
            # its routes are attributed only to the Mount-expanded
            # (prefixed) endpoints, never the free-floating pass.
            # Methods are keyed by `Receiver.Method` so an
            # unmounted same-named method (e.g. a top-level
            # `func (s server) Routes()` used directly) keeps its
            # routes — and the `.Mount(...)` calls inside it.
            decl_name = nil
            if func_match = line.match(/func\s+\(\s*\w+\s+\*?([\w.]+)\)\s+([a-zA-Z_]\w*)\s*\(/)
              decl_name = "#{func_match[1].split('.').last}.#{func_match[2]}"
            elsif func_match = line.match(/func\s+([a-zA-Z_]\w*)\s*\(/)
              decl_name = func_match[1]
            end
            if decl_name && mounted_functions.includes?(decl_name)
              in_mounted_func = true
              mounted_func_brace_count = line.count("{") - line.count("}")
              if mounted_func_brace_count <= 0
                in_mounted_func = false
              end
              next
            end
          end

          details = Details.new(PathInfo.new(path, index + 1))

          if line.includes?(".Mount(")
            if (target = parse_mount_target(line, string_values_for(dir))) &&
               (target_dir = resolve_mount_dir(path, dir, target, file_contents_cache))
              endpoints = expand_mounted_router(target_dir, target[:func_name], target[:recv_type],
                package_files, file_contents_cache, file_lines_cache, [] of String)
              endpoints.each do |ep|
                ep.url = mount_join(target[:prefix], ep.url)
                result << ep
              end
            end
            next
          end
          next unless chi_file

          # Emit any route whose declaration begins on this line,
          # and seed inline-handler tracking so the param extractor
          # below only attributes params to the enclosing route.
          if ts_hits = routes_by_line[index]?
            ts_hits.each do |route|
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                endpoint = Endpoint.new(route.path, verb, details)
                if entries = callees_by_route[route.line]?
                  entries.each do |entry|
                    name, callee_path, callee_line = entry
                    endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                  end
                end
                result << endpoint
                last_endpoint = endpoint
              end
            end
            if line.includes?("func(")
              state.in_inline_handler = true
              state.handler_brace_count = line.count("{") - line.count("}")
              if state.handler_brace_count <= 0
                state.in_inline_handler = false
                state.handler_brace_count = 0
              end
            end
          elsif state.in_inline_handler?
            # Normal line inside an inline handler — tally braces
            # so we know when it closes.
            state.handler_brace_count += line.count("{")
            state.handler_brace_count -= line.count("}")
            if state.handler_brace_count <= 0
              state.in_inline_handler = false
              state.handler_brace_count = 0
            end
          end

          extract_params(line, state, last_endpoint)
        end
      end
      result
    end

    private def extract_params(line : String, state : ChiRouteState, last_endpoint : Endpoint)
      return if last_endpoint.url.empty?
      return unless state.in_inline_handler?

      # Parameter extraction patterns (order matters - check more specific patterns first)
      pattern = if line.includes?("chi.URLParam(")
                  "URLParam"
                elsif line.includes?("Query().Get(")
                  "Query"
                elsif line.includes?("PostFormValue(")
                  "PostFormValue"
                elsif line.includes?("FormValue(")
                  "FormValue"
                elsif line.includes?("Header.Get(")
                  "Header"
                elsif line.includes?("Cookie(")
                  "Cookie"
                end

      if pattern
        param = get_param(line, pattern)
        last_endpoint.params << param unless param.name.empty?
      end

      # Body-binding helpers that consume `r.Body` directly. Chi
      # apps commonly pair the stdlib `json.NewDecoder(r.Body).Decode`
      # idiom with go-chi/render's `render.DecodeJSON` / `render.Bind`.
      # All three indicate the handler reads a request body.
      if line.matches?(/json\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/) ||
         line.includes?("render.DecodeJSON(") ||
         line.includes?("render.Bind(")
        body_param = Param.new("body", "", "json")
        last_endpoint.params << body_param unless last_endpoint.params.includes?(body_param)
      end
    end

    def get_param(line : String, pattern : String) : Param
      param_name = ""
      param_type = ""

      # Special handling for different patterns
      case pattern
      when "URLParam"
        # Handle chi.URLParam(r, "id") pattern
        if match = line.match(/chi\.URLParam\([^,]+,\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "path"
        end
      when "Query"
        # Handle r.URL.Query().Get("name") pattern
        if match = line.match(/Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "query"
        end
      when "PostFormValue"
        # Handle r.PostFormValue("username") pattern
        if match = line.match(/PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "FormValue"
        # Handle r.FormValue("password") pattern
        if match = line.match(/FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "Header"
        # Handle r.Header.Get("User-Agent") pattern
        if match = line.match(/Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "header"
        end
      when "Cookie"
        # Handle r.Cookie("auth_token") pattern
        if match = line.match(/Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "cookie"
        end
      end

      Param.new(param_name, "", param_type)
    end

    # Parses a `.Mount("/prefix", target())` line into its mount prefix
    # and the declaration that builds the sub-router. The prefix is a
    # string literal or an identifier `string_values` can pin down
    # (`prefix := "/api/actions"; r.Mount(prefix, ...)`). Four target
    # shapes are recognized:
    #   * plain function   — `r.Mount("/admin", adminRouter())`
    #     -> {func_name: "adminRouter", recv_type: nil, pkg_alias: nil}
    #   * package-qualified function — `r.Mount("/api/v1", apiv1.Routes())`
    #     -> {func_name: "Routes", recv_type: nil, pkg_alias: "apiv1"}
    #     (resolved to a directory by `resolve_mount_dir`)
    #   * struct value-method (chi's idiomatic REST "resource" pattern) —
    #     `r.Mount("/todos", todosResource{}.Routes())`
    #     -> {func_name: "Routes", recv_type: "todosResource"}
    #   * pointer-receiver method — `r.Mount("/x", (&Type{}).Routes())`
    # The receiver type is kept so two resources that both expose a
    # `Routes()` method resolve to their own bodies, not the first one
    # found. Call arguments are allowed (`actions.Routes(prefix)`) —
    # the body is what matters. Returns nil for unsupported targets
    # (a bare variable `r.Mount("/x", sub)`, or a prefix that cannot be
    # resolved to one string).
    private def parse_mount_target(line : String, string_values : Hash(String, String) = Hash(String, String).new) : MountTarget?
      m = line.match(/\.Mount\(\s*(?:"([^"]*)"|([A-Za-z_]\w*))\s*,\s*(.*)$/)
      return unless m
      prefix = m[1]?
      if prefix.nil?
        prefix = string_values[m[2]]?
        return unless prefix
      end
      rest = m[3]
      # Value-receiver method: `Type{}.Routes()` / `pkg.Type{...}.Routes()`.
      if t = rest.match(/^([\w.]+)\s*\{[^{}]*\}\s*\.\s*(\w+)\s*\(/)
        return {prefix: prefix, func_name: t[2], recv_type: t[1].split('.').last, pkg_alias: nil}
      end
      # Pointer-receiver method: `(&Type{}).Routes()` — the only valid Go
      # syntax for a pointer-receiver resource (`.` binds tighter than
      # `&`, so the parens are required).
      if t = rest.match(/^\(\s*&\s*([\w.]+)\s*\{[^{}]*\}\s*\)\s*\.\s*(\w+)\s*\(/)
        return {prefix: prefix, func_name: t[2], recv_type: t[1].split('.').last, pkg_alias: nil}
      end
      # Plain or package-qualified function: `adminRouter()`,
      # `apiv1.Routes()`, `actions.Routes(prefix)`.
      if t = rest.match(/^(?:(\w+)\.)?(\w+)\s*\(/)
        return {prefix: prefix, func_name: t[2], recv_type: nil, pkg_alias: t[1]?}
      end
      nil
    end

    alias MountTarget = NamedTuple(prefix: String, func_name: String, recv_type: String?, pkg_alias: String?)

    # Skip key for a parsed mount target: a method target is keyed by
    # `Receiver.Method` so the free pass skips only the exact mounted
    # method body, while a plain-function target is keyed by its bare
    # name. Mirrors the keys produced when scanning declarations.
    private def mount_skip_key(target : MountTarget) : String
      if rt = target[:recv_type]
        "#{rt}.#{target[:func_name]}"
      else
        target[:func_name]
      end
    end

    # Directory whose package declares the mount target. A plain or
    # receiver target is declared in the mounting file's own package; a
    # package-qualified one goes through the file's import block and the
    # go.mod-backed import-path index. Nil when the alias is not a local
    # package (`middleware.Profiler()` from chi itself, `http.StripPrefix`).
    private def resolve_mount_dir(file_path : String, dir : String, target : MountTarget,
                                  file_contents_cache : Hash(String, String)) : String?
      alias_name = target[:pkg_alias]
      return dir unless alias_name
      return if @import_dirs.empty?
      aliases = @import_aliases_cache[file_path]? || begin
        content = file_contents_cache[file_path]? || read_file_content(file_path)
        @import_aliases_cache[file_path] = Noir::GoCalleeExtractor.extract_import_aliases(content)
      end
      import_path = aliases[alias_name]?
      return unless import_path
      @import_dirs[import_path]?
    end

    # Route paths from the walker always start with `/` (or are empty for
    # a `m.Get("", h)` at the router root), so joining is a matter of not
    # doubling the slash when the mount prefix is `/` or `` — gitea mounts
    # its web router at `/` and `r.Mount("/", web.Routes())` must not
    # turn `/metrics` into `//metrics`.
    private def mount_join(prefix : String, url : String) : String
      base = prefix.rstrip('/')
      if base.empty?
        return url.empty? ? "/" : url
      end
      return base if url.empty?
      url.starts_with?("/") ? "#{base}#{url}" : "#{base}/#{url}"
    end

    private def string_values_for(dir : String) : Hash(String, String)
      @package_string_values[dir]? || EMPTY_STRING_VALUES
    end

    EMPTY_STRING_VALUES = Hash(String, String).new

    # Nested `Mount` calls inside a mounted router are followed to this
    # depth; deeper trees are almost certainly a cycle through a symbol
    # the resolver could not tell apart.
    MAX_MOUNT_DEPTH = 8

    # Extracts endpoints from a router function definition declared in
    # the Go package at `dir`, searching every `.go` file there.
    #
    # Uses the tree-sitter walker, scoped down to just the target
    # function's declaration so the returned routes are relative to the
    # function body — the caller slaps on the Mount prefix. When
    # `recv_type` is given, the target is a method (`func (r Type) Name()`)
    # and only the declaration on that receiver type is matched.
    #
    # `.Mount(...)` calls inside the body are expanded recursively with
    # their own prefix, so `apiRouter()` mounting `usersRouter()` at
    # `/users` yields `/users/...` relative to `apiRouter`'s root. The
    # `ancestors` list guards against a router that (transitively)
    # mounts itself.
    def expand_mounted_router(dir : String, func_name : String, recv_type : String?,
                              package_files : Hash(String, Array(String)),
                              file_contents_cache : Hash(String, String),
                              file_lines_cache : Hash(String, Array(String)),
                              ancestors : Array(String)) : Array(Endpoint)
      endpoints = [] of Endpoint
      key = "#{dir}|#{recv_type}.#{func_name}"
      return endpoints if ancestors.includes?(key) || ancestors.size >= MAX_MOUNT_DEPTH
      files = package_files[dir]?
      return endpoints unless files

      files.each do |search_path|
        content =
          file_contents_cache[search_path]? ||
            begin
              read_file_content(search_path)
            rescue IO::Error
              next
            end

        found = false
        nested = [] of Endpoint
        string_values = string_values_for(dir)
        Noir::TreeSitter.parse_go(content) do |root|
          find_func_declaration(root, content, func_name, recv_type) do |body|
            found = true
            # Re-run the chi walker against the isolated body. skip_functions
            # is empty because any nested func literal inside is the inline
            # handler which the walker already ignores by convention.
            collected = [] of Noir::TreeSitterGoRouteExtractor::Route
            helpers = Noir::TreeSitterGoRouteExtractor.collect_route_helpers(root, content)
            Noir::TreeSitterGoRouteExtractor.walk_chi_public(body, content, collected, string_values, helpers)
            # Capture routes' original line numbers on the endpoint details.
            # `attach_router_function_params` uses those to bind parameter
            # lines to the correct endpoint instead of counting verb calls,
            # which would false-positive on `r.Header.Get(...)` / `Query().Get(...)`
            # accessor calls inside inline handlers.
            collected.each do |route|
              details = Details.new(PathInfo.new(search_path, route.line + 1))
              Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                endpoints << Endpoint.new(route.path, verb, details)
              end
            end

            lines = file_lines_cache[search_path]? || content.lines
            first_row = Noir::TreeSitter.node_start_row(body)
            last_row = Noir::TreeSitter.node_end_row(body)
            row = first_row
            while row <= last_row && row < lines.size
              line = lines[row]
              row += 1
              next unless line.includes?(".Mount(")
              target = parse_mount_target(line, string_values)
              next unless target
              target_dir = resolve_mount_dir(search_path, dir, target, file_contents_cache)
              next unless target_dir
              expand_mounted_router(target_dir, target[:func_name], target[:recv_type],
                package_files, file_contents_cache, file_lines_cache, ancestors + [key]).each do |ep|
                ep.url = mount_join(target[:prefix], ep.url)
                nested << ep
              end
            end
          end
        end
        next unless found

        lines = file_lines_cache[search_path]? || content.lines
        attach_router_function_params(endpoints, lines)
        endpoints.concat(nested)
        break
      end

      endpoints
    end

    # Twin of `GoEngine#collect_go_modules`; chi extends `Analyzer`
    # directly so it cannot inherit it. `{module path, directory}` per
    # `go.mod` in the tree, deepest directory first so a nested module
    # wins over the one that contains it.
    private def collect_go_modules : Array(Tuple(String, String))
      modules = [] of Tuple(String, String)
      get_files_by_basename("go.mod").each do |path|
        next if base_relative_path(path).includes?("/vendor/")
        begin
          content = read_file_content(path)
        rescue IO::Error
          next
        end
        match = content.match(/^\s*module\s+(\S+)/m)
        next unless match
        modules << {match[1], File.expand_path(File.dirname(path))}
      end
      modules.sort_by! { |(_module_path, mod_dir)| -mod_dir.size }
      modules
    end

    private def import_path_for_dir(dir : String, modules : Array(Tuple(String, String))) : String?
      expanded_dir = File.expand_path(dir)
      modules.each do |module_path, module_dir|
        next unless expanded_dir == module_dir || expanded_dir.starts_with?("#{module_dir}/")
        rel = expanded_dir[module_dir.size..].lstrip("/")
        return rel.empty? ? module_path : "#{module_path}/#{rel}"
      end
      nil
    end

    private def find_func_declaration(node : LibTreeSitter::TSNode, source : String, name : String, recv_type : String? = nil, &block : LibTreeSitter::TSNode ->)
      node_ty = Noir::TreeSitter.node_type(node)
      # A plain function (`func Name()`) matches when no receiver type was
      # requested; a method (`func (r Type) Name()`) matches only when its
      # receiver type equals `recv_type`.
      wanted_ty = recv_type ? "method_declaration" : "function_declaration"
      if node_ty == wanted_ty
        if name_node = Noir::TreeSitter.field(node, "name")
          if Noir::TreeSitter.node_text(name_node, source) == name &&
             (recv_type.nil? || method_receiver_type(node, source) == recv_type)
            if body = Noir::TreeSitter.field(node, "body")
              yield body
              return
            end
          end
        end
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        find_func_declaration(child, source, name, recv_type, &block)
      end
    end

    # Returns the (package-unqualified, pointer-stripped) receiver type name
    # of a `method_declaration` — `func (rs todosResource) Routes()` ->
    # "todosResource", `func (s *Server) Routes()` -> "Server".
    private def method_receiver_type(node : LibTreeSitter::TSNode, source : String) : String?
      receiver = Noir::TreeSitter.field(node, "receiver")
      return unless receiver
      type_name = nil
      Noir::TreeSitter.each_named_child(receiver) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "parameter_declaration"
        if type_node = Noir::TreeSitter.field(decl, "type")
          type_name = Noir::TreeSitter.node_text(type_node, source)
        end
      end
      return unless type_name
      type_name.lchop('*').split('.').last
    end

    # Reattach the line-based param extractor to mount-expanded endpoints.
    # Endpoints arrive with their source line recorded in PathInfo.line
    # (1-based), so we index them by line and switch `last_endpoint`
    # whenever the walker crosses a declaration line — much more robust
    # than counting verb-shaped method calls, since inline handlers
    # invoke `r.Header.Get(...)` and friends that would otherwise shift
    # the iterator off-by-one.
    private def attach_router_function_params(endpoints : Array(Endpoint), lines : Array(String))
      return if endpoints.empty?

      endpoints_by_line = Hash(Int32, Endpoint).new
      endpoints.each do |ep|
        ep.details.code_paths.each do |cp|
          if line = cp.line
            endpoints_by_line[line.to_i - 1] = ep
          end
        end
      end
      return if endpoints_by_line.empty?

      min_line = endpoints_by_line.keys.min
      max_line = endpoints_by_line.keys.max

      state = ChiRouteState.new
      last_endpoint = Endpoint.new("", "")

      # Scan from the earliest declaration line forward until every
      # endpoint has had a chance to absorb its handler body. The handler
      # brace count terminates the body window; we stop when we've gone
      # well past the last endpoint and no handler is open.
      index = min_line
      while index < lines.size
        line = lines[index]
        if ep = endpoints_by_line[index]?
          last_endpoint = ep
          if line.includes?("func(")
            state.in_inline_handler = true
            state.handler_brace_count = line.count("{") - line.count("}")
            if state.handler_brace_count <= 0
              state.in_inline_handler = false
              state.handler_brace_count = 0
            end
          end
        elsif state.in_inline_handler?
          state.handler_brace_count += line.count("{")
          state.handler_brace_count -= line.count("}")
          if state.handler_brace_count <= 0
            state.in_inline_handler = false
            state.handler_brace_count = 0
          end
        end

        extract_params(line, state, last_endpoint)

        break if index > max_line && !state.in_inline_handler?
        index += 1
      end
    end
  end
end
