require "../../models/analyzer"
require "../../miniparsers/go_callee_extractor"
require "../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class GoEngine < Analyzer
    # `*_test.go` is Go's hard-wired build-tag for test-only source.
    # `go build` excludes these files entirely; only `go test` pulls
    # them in. Real route handlers never live there, but framework
    # repos (echo, chi, gin) park hundreds of `e.GET("/...", ...)`
    # calls in `*_test.go` to exercise the router. Skip both in the
    # cross-file pre-passes (so test-file groups don't pollute the
    # production group map) and in each analyzer's per-file loop.
    #
    # Also skip Go's toolchain-ignored directory prefixes: any
    # path component starting with `_` (`_examples/`, `_assets/`,
    # `_testdata/`) is excluded by `go build`/`go list` outright.
    # `kataras/iris` alone parks 392 phantom endpoints under
    # `_examples/...`; they're documented apps, not production
    # routes the framework ships.
    def self.go_test_file?(path : String) : Bool
      return true if path.ends_with?("_test.go")
      path.split("/").any?(&.starts_with?("_"))
    end

    # --- Tree-sitter group/route pre-pass --------------------------------
    #
    # Does a cross-file fixpoint over every `.go` file in each package
    # directory, extracting group declarations (`x := r.Group("/x")` and
    # friends). Returns:
    #   * `package_groups` — per-directory `{group_name => resolved_prefix}`
    #   * `file_contents` — cached source strings keyed by path, so the
    #     per-file second pass doesn't read files twice
    #
    # `group_method` is the method name used for grouping — `"Group"` for
    # Gin/Echo/Fiber/Hertz (default), `"Party"` for Iris, `"Subrouter"`
    # for Mux.
    #
    # The fixpoint handles the `routes.go` calling `v1.GET(...)` under a
    # `v1 := r.Group("/v1")` declared in `main.go` case — iterate until
    # no new entries land. In-file declarations win over external ones.
    # `import_marker`, when given, restricts the cross-file group/engine
    # pre-pass to files that actually import the framework. Group
    # variables (`v1 := r.Group("/v1")`) and root-engine bindings only
    # ever appear in framework-importing files, so skipping the rest
    # avoids parsing unrelated `.go` files — a large saving in mixed
    # repos (e.g. an example monorepo where most dirs use other routers).
    # `file_contents` is still populated for every file so the per-file
    # route pass and callee pre-pass keep their read cache.
    def collect_package_groups_ts(group_method : String = "Group", import_marker : String? = nil) : Tuple(Hash(String, Hash(String, String)), Hash(String, String))
      package_groups = Hash(String, Hash(String, String)).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents = Hash(String, String).new

      get_files_by_extension(".go").each do |path|
        next if File.directory?(path)
        next if GoEngine.go_test_file?(path)
        dir = File.dirname(path)
        files_by_dir[dir] ||= [] of String
        files_by_dir[dir] << path
      end

      files_by_dir.each do |_dir, paths|
        paths.each do |path|
          begin
            file_contents[path] = read_file_content(path)
          rescue File::NotFoundError
            # skip
          end
        end
      end

      files_by_dir.each do |dir, paths|
        relevant = if import_marker
                     paths.select { |p| (c = file_contents[p]?) && c.includes?(import_marker) }
                   else
                     paths
                   end
        next if relevant.empty?

        # Detect group-variable names that resolve to DIFFERENT prefixes
        # across files of the same package. These are almost always
        # function-local names (`r`, `g`, `api`, ...) reused across
        # separate handler functions, not genuinely shared package
        # groups. Each name's binding is computed from its OWN file only
        # (empty external map) so the decision is immune to cross-file
        # pollution. Conflicting names are excluded from the shared map
        # below — propagating them would let one function's local binding
        # contaminate another's routes. (Observed in go-admin:
        # `r := v1.Group("/dept")` in one handler file leaked a spurious
        # `/dept` prefix onto `v1` and therefore onto every route in the
        # package: `/dept/api/v1/...`.) Each file still re-derives these
        # names locally during route extraction, so same-file resolution
        # is unaffected.
        #
        # Root engine/router names (`r := gin.New()`, `func(r
        # *gin.Engine)`) are folded into the same parse and likewise added
        # to `ambiguous` so a same-named local group in a sibling file
        # (e.g. `r := v1.Group("/sysjob")`) can't leak its prefix onto the
        # root and pollute `v1 := r.Group("/api/v1")` (observed:
        # `/sysjob/api/v1/...`).
        ambiguous = Set(String).new
        local_values = Hash(String, String).new
        own_groups_by_file = Hash(String, Hash(String, String)).new
        relevant.each do |path|
          content = file_contents[path]?
          next if content.nil?
          names, own = Noir::TreeSitterGoRouteExtractor.extract_engine_names_and_groups(content, group_method)
          names.each { |n| ambiguous << n }
          own_groups_by_file[path] = own
          own.each do |k, v|
            next if ambiguous.includes?(k)
            if (existing = local_values[k]?) && existing != v
              ambiguous << k
              local_values.delete(k)
            else
              local_values[k] = v
            end
          end
        end

        groups = Hash(String, String).new
        if relevant.size == 1
          # A single-file package can't propagate prefixes across files,
          # so its own-file groups (already parsed above) are final — skip
          # the cross-file fixpoint and its redundant re-parse entirely.
          own = own_groups_by_file[relevant.first]?
          own.try &.each do |k, v|
            next if ambiguous.includes?(k)
            groups[k] = v
          end
        else
          loop do
            prev_size = groups.size
            relevant.each do |path|
              content = file_contents[path]?
              next if content.nil?
              found = Noir::TreeSitterGoRouteExtractor.extract_groups(content, groups, group_method)
              found.each do |k, v|
                next if ambiguous.includes?(k)
                groups[k] ||= v
              end
            end
            break if groups.size == prev_size
          end
        end
        package_groups[dir] = groups unless groups.empty?
      end

      {package_groups, file_contents}
    end

    # Returns the cross-file group map for the given directory, or an
    # empty map when the directory has no registered groups.
    def ts_groups_for_directory(package_groups : Hash(String, Hash(String, String)), dir : String) : Hash(String, String)
      package_groups[dir]? || Hash(String, String).new
    end

    GO_HTTP_ROUTE_CALL_RE = /\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Get|Post|Put|Delete|Patch|Head|Options|ANY|Any|All)\s*\(/

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the per-framework extra route methods are
    # a small fixed set per analyzer, so memoize their matchers per name
    # instead of rebuilding them for every candidate file.
    @extra_method_regexes = Hash(String, Regex).new

    # Per-package directories that import a target framework. Some real
    # projects hide the concrete framework type behind a local interface, so
    # the file that calls `router.GET(...)` may not import Gin/Echo itself.
    def framework_package_dirs(file_contents : Hash(String, String), import_marker : String) : Set(String)
      dirs = Set(String).new
      file_contents.each do |path, content|
        dirs << File.dirname(path) if content.includes?(import_marker)
      end
      dirs
    end

    # Cheap gate before the tree-sitter route pass. Handler-only files often
    # import Gin/Echo for `*gin.Context` / `echo.Context`, but they cannot emit
    # endpoints unless they contain a route/static registration call.
    def go_route_source_candidate?(content : String, extra_methods : Array(String)) : Bool
      return true if content.matches?(GO_HTTP_ROUTE_CALL_RE)
      extra_methods.any? do |method|
        method_regex = @extra_method_regexes[method] ||= /\.#{Regex.escape(method)}\s*\(/
        content.matches?(method_regex)
      end
    end

    def framework_route_source_candidate?(content : String,
                                          dir : String,
                                          framework_dirs : Set(String),
                                          import_marker : String,
                                          extra_methods : Array(String)) : Bool
      return false unless content.includes?(import_marker) || framework_dirs.includes?(dir)
      go_route_source_candidate?(content, extra_methods)
    end

    # --- Cross-file function body pre-pass --------------------------------
    #
    # Walks every cached `.go` source in `file_contents` and collects
    # top-level `function_declaration` nodes into a per-directory map
    # so cross-file identifier-handler resolution in
    # `Noir::GoCalleeExtractor` is O(1) at lookup time. The map is
    # keyed by directory because Go's name resolution rules are scoped
    # to a single package (== single directory), so we never have to
    # worry about cross-package leakage.
    def collect_package_function_bodies(file_contents : Hash(String, String)) : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody))
      result = Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)).new
      return result unless callees_needed?
      file_contents.each do |path, content|
        dir = File.dirname(path)
        fns = Noir::GoCalleeExtractor.collect_function_bodies(content, path)
        next if fns.empty?
        result[dir] ||= Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
        fns.each { |name, fb| result[dir][name] ||= fb }
      end
      result
    end

    # Builds `{import_path => {function_name => body}}` for local Go
    # packages under the configured base paths. This is gated on callee
    # demand and reuses `package_function_bodies`, so default route scans
    # do not pay for go.mod discovery. It lets generated routers like
    # Hertz resolve `feed.Feed` when `feed` imports a sibling package from
    # the same module.
    def collect_import_path_function_bodies(package_function_bodies : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody))) : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody))
      result = Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)).new
      return result unless callees_needed?

      modules = collect_go_modules
      return result if modules.empty?

      package_function_bodies.each do |dir, functions|
        next if functions.empty?
        import_path = import_path_for_dir(dir, modules)
        next unless import_path
        result[import_path] = functions
      end

      result
    end

    # Builds `{import_path => {method_name => [body, ...]}}` for local Go
    # packages under the configured base paths. This complements
    # `collect_import_path_function_bodies` for route handlers referenced
    # as method values on imported package instances, e.g.
    # `handler := api.NewHandler(svc); app.Get("/x", handler.Show)`.
    def collect_import_path_method_bodies(package_method_bodies : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)))) : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)))
      result = Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))).new
      return result unless callees_needed?

      modules = collect_go_modules
      return result if modules.empty?

      package_method_bodies.each do |dir, methods|
        next if methods.empty?
        import_path = import_path_for_dir(dir, modules)
        next unless import_path
        result[import_path] = methods
      end

      result
    end

    # Returns the cross-file function-body map for the given directory,
    # or an empty map when the directory has no captured functions.
    def ts_function_bodies_for_directory(package_function_bodies : Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)), dir : String) : Hash(String, Noir::GoCalleeExtractor::FunctionBody)
      package_function_bodies[dir]? || Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
    end

    # --- Beego controller-method pre-pass --------------------------------
    #
    # Builds a per-directory `{controller_type => [http_verb_methods]}` map
    # so mapping-less `web.Router("/x", &Ctrl{})` registrations resolve to
    # the exact methods the controller implements. Keyed by directory
    # because Beego controllers and their router registrations share a Go
    # package (== directory); a controller defined in a sibling file is
    # still found.
    def collect_package_controller_methods(file_contents : Hash(String, String)) : Hash(String, Hash(String, Array(String)))
      result = Hash(String, Hash(String, Array(String))).new
      file_contents.each do |path, content|
        # Cheap gate: a file with controller methods must contain a method
        # receiver. gofmt always writes those as `func (recv Type) Name(`,
        # so files without `func (` can't define controller methods and
        # are skipped before paying for a tree-sitter parse.
        next unless content.includes?("func (")
        methods = Noir::TreeSitterGoRouteExtractor.extract_controller_methods(content)
        next if methods.empty?
        dir = File.dirname(path)
        dir_map = (result[dir] ||= Hash(String, Array(String)).new)
        methods.each do |type_name, names|
          list = (dir_map[type_name] ||= [] of String)
          names.each { |n| list << n unless list.includes?(n) }
        end
      end
      result
    end

    # Returns the cross-file controller-method map for the given
    # directory, or an empty map.
    def ts_controller_methods_for_directory(package_controller_methods : Hash(String, Hash(String, Array(String))), dir : String) : Hash(String, Array(String))
      package_controller_methods[dir]? || Hash(String, Array(String)).new
    end

    # Per-directory `{method_name => [FunctionBody, ...]}` map for
    # controller-style routes whose handler is referenced by method name
    # (Beego's `web.Router("/x", &Ctrl{}, "get:Method")`). Lets the
    # analyzer walk the controller method's body for callees even though
    # the registration call doesn't pass the handler as an argument.
    # Gated on `callees_needed?` so default scans pay nothing.
    def collect_package_controller_method_bodies(file_contents : Hash(String, String)) : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)))
      result = Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))).new
      return result unless callees_needed?
      file_contents.each do |path, content|
        next unless content.includes?("func (")
        methods = Noir::GoCalleeExtractor.collect_method_bodies(content, path)
        next if methods.empty?
        dir = File.dirname(path)
        dir_map = (result[dir] ||= Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new)
        methods.each do |name, list|
          (dir_map[name] ||= [] of Noir::GoCalleeExtractor::FunctionBody).concat(list)
        end
      end
      result
    end

    def ts_controller_method_bodies_for_directory(package_controller_method_bodies : Hash(String, Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))), dir : String) : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))
      package_controller_method_bodies[dir]? || Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new
    end

    # Read every `.go` file once into a `{path => source}` hash. Used by
    # analyzers (Goyave) that don't otherwise call
    # `collect_package_groups_ts` but still need the file_contents hash
    # as input to `collect_package_function_bodies`.
    def read_package_file_contents : Hash(String, String)
      file_contents = Hash(String, String).new
      get_files_by_extension(".go").each do |path|
        next if File.directory?(path)
        next if GoEngine.go_test_file?(path)
        begin
          file_contents[path] = read_file_content(path)
        rescue File::NotFoundError
          # skip
        end
      end
      file_contents
    end

    # --- Adapter helpers (shared across Go framework adapters) ----------

    def add_param_to_endpoint(param : Param, endpoint : Endpoint)
      if param.name.size > 0 && !endpoint.method.empty? && !endpoint.url.empty?
        # Don't re-add an identical (name, type) param. go-zero's
        # handler-body getters (`httpx.ParseForm`, repeated across several
        # handlers in a single-file app) would otherwise stack four
        # `body` params onto one endpoint; the same guard keeps every Go
        # adapter's line-loop from emitting duplicates.
        return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
        endpoint.params << param
      end
    end

    def add_static_path_if_valid(static_path : Hash(String, String), public_dirs : Array(Hash(String, String)))
      if static_path["static_path"].size > 0 && static_path["file_path"].size > 0
        public_dirs << static_path
      end
    end

    def static_dir_entry(source_path : String, static_path : String, file_path : String) : Hash(String, String)
      {
        "static_path" => static_path,
        "file_path"   => file_path,
        "source_path" => source_path,
      }
    end

    def resolve_public_dirs_with_glob(public_dirs : Array(Hash(String, String)))
      public_dirs.each do |p_dir|
        next if p_dir["file_path"].size == 0
        full_path = resolve_public_dir_path(p_dir)

        next unless File.directory?(full_path)
        Dir.glob("#{escape_glob_path(full_path)}/**/*") do |path|
          next if File.directory?(path)
          if File.exists?(path)
            static_url = p_dir["static_path"]
            if static_url.ends_with?("/")
              static_url = static_url[0..-2]
            end

            details = Details.new(PathInfo.new(path))
            result << Endpoint.new("#{static_url}#{path.gsub(full_path, "")}", "GET", details)
          end
        end
      end
    end

    def resolve_public_dirs(public_dirs : Array(Hash(String, String)))
      public_dirs.each do |p_dir|
        full_path = resolve_public_dir_path(p_dir)

        get_files_by_prefix(full_path).each do |path|
          # Ensure strict prefix match (directory boundary or exact match)
          # get_files_by_prefix matches any file starting with prefix, so "public" matches "public2"
          # We prevent this by ensuring the next character is a separator or it's an exact match
          next unless path == full_path || path.starts_with?(full_path.ends_with?("/") ? full_path : "#{full_path}/")

          if File.exists?(path)
            if p_dir["static_path"].ends_with?("/")
              p_dir["static_path"] = p_dir["static_path"][0..-2]
            end

            details = Details.new(PathInfo.new(path))
            result << Endpoint.new("#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET", details)
          end
        end
      end
    end

    private def resolve_public_dir_path(p_dir : Hash(String, String)) : String
      file_path = p_dir["file_path"]
      return Path[file_path].normalize.to_s if file_path.starts_with?("/") && Dir.exists?(file_path)

      normalized_file_path = file_path.lstrip("/")
      root = base_path
      if source_path = p_dir["source_path"]?
        source_dir = File.dirname(source_path)
        source_relative = Path[(source_dir + "/" + normalized_file_path).gsub_repeatedly("//", "/")].normalize.to_s
        if Dir.exists?(source_relative)
          return preserve_relative_prefix(source_relative, source_path)
        end

        root = base_path_for_path(source_path)
      end

      raw_full_path = (root + "/" + normalized_file_path).gsub_repeatedly("//", "/")
      normalized_full_path = Path[raw_full_path].normalize.to_s

      if root.starts_with?("./") && !normalized_full_path.starts_with?("./") && !normalized_full_path.starts_with?("/")
        "./#{normalized_full_path}"
      else
        normalized_full_path
      end
    end

    private def preserve_relative_prefix(path : String, reference : String) : String
      if reference.starts_with?("./") && !path.starts_with?("./") && !path.starts_with?("/")
        "./#{path}"
      else
        path
      end
    end

    private def base_path_for_path(path : String) : String
      configured_base_for(path)
    end

    private def collect_go_modules : Array(Tuple(String, String))
      modules = [] of Tuple(String, String)
      all_files.each do |path|
        next unless File.basename(path) == "go.mod"
        next if File.directory?(path)
        next if path.split("/").includes?("vendor")

        begin
          content = read_file_content(path)
        rescue File::NotFoundError
          next
        end

        match = content.match(/^\s*module\s+(\S+)/m)
        next unless match
        modules << {match[1], File.expand_path(File.dirname(path))}
      end

      modules.sort_by! { |(_module_path, dir)| -dir.size }
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
  end
end
