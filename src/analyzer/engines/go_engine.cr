require "../../models/analyzer"
require "../../miniparsers/go_callee_extractor"
require "../../miniparsers/go_route_extractor_ts"
require "../../miniparsers/go_named_handler"
require "../../miniparsers/go_struct_fields"
require "../../miniparsers/go_request_param_extractor"
require "../../utils/worker_threads"
require "../../utils/c_comments"

module Analyzer::Go
  # `GoEngine.go_test_file?` judged from the file's own module. Go's `_` and
  # `testdata` exclusions are relative to the module, and a nested module is
  # its own root: chi's `_examples/rest/go.mod` builds `_examples/rest` as an
  # ordinary package, so its routes count whether the scan starts at the repo
  # or at `_examples`. Included by every Go analyzer, engine or not.
  module GoTestPath
    @go_module_roots : Array(String)?
    @go_test_module_roots : Set(String)?

    # `module github.com/acme/app/tests`: a module named for a test tree is
    # built by the test run only. Infisical's integration-test module keeps
    # its fake upstream servers (`tests/fakes/github/fake.go`) there.
    GO_MODULE_LINE_RE    = /^\s*module\s+["`]?([^\s"`]+)/m
    GO_TEST_MODULE_NAMES = Set{"test", "tests", "e2e"}

    def go_test_path?(path : String) : Bool
      relative = base_relative_path(path)
      # `test/`, `tests/` and `e2e/` are conventions, not a toolchain rule,
      # so they stay on the scan-base path. Re-judging them from a nested
      # module root would keep `test/e2e/*.go` whenever that tree had its
      # own go.mod. A scan started at a directory named `test` does not
      # match: the base name is not part of `relative`. `integration/` is
      # not in the set: it is a common production package.
      return true if GoEngine.go_test_dir?(relative)
      unless go_test_module_roots.empty?
        absolute = go_slash_path(Noir::PathScope.expand(path))
        root = go_module_roots.find { |dir| absolute.starts_with?(dir) }
        return true if root && go_test_module_roots.includes?(root)
      end
      return false unless GoEngine.go_test_file?(relative)
      return true if relative.ends_with?("_test.go")
      absolute = go_slash_path(Noir::PathScope.expand(path))
      root = go_module_roots.find { |dir| absolute.starts_with?(dir) }
      # The module root lies inside the scan base (its go.mod is a scanned
      # file), so the module-relative path is a suffix of `relative`.
      root ? GoEngine.go_test_file?(absolute[root.size - 1..]) : true
    end

    # Expanded directories of the scan's go.mod files, with a trailing `/`,
    # deepest first.
    private def go_module_roots : Array(String)
      @go_module_roots ||= get_files_by_basename("go.mod")
        .map { |p| go_slash_path(Noir::PathScope.expand(File.dirname(p))).rstrip('/') + "/" }
        .sort_by! { |dir| -dir.size }
    end

    # Module roots (as in `go_module_roots`) of the test-named modules nested
    # in the scan. A scan started at such a module keeps it: that is the
    # project being asked about.
    private def go_test_module_roots : Set(String)
      @go_test_module_roots ||= get_files_by_basename("go.mod").compact_map do |go_mod|
        next if base_relative_path(go_mod) == "/go.mod"
        name = read_file_content(go_mod).match(GO_MODULE_LINE_RE).try(&.[1]) || next
        next unless GO_TEST_MODULE_NAMES.includes?(name.split('/').last)
        go_slash_path(Noir::PathScope.expand(File.dirname(go_mod))).rstrip('/') + "/"
      rescue File::Error | IO::Error
        nil
      end.to_set
    end

    private def go_slash_path(path : String) : String
      File::SEPARATOR == '/' ? path : path.gsub(File::SEPARATOR, '/')
    end
  end

  abstract class GoEngine < Analyzer
    # Conventional test-only trees that `go build` still compiles when
    # they are ordinary packages: `test/`, `tests/`, `e2e/`.
    # Shopify/toxiproxy parks a bench router in `test/e2e/endpoint.go`
    # (not `*_test.go`); `/test1` and `/test2` are not the API. Whole
    # segments only, so `testing/` and `testutil/` stay. `integration/`
    # is left out on purpose: `internal/integration/slack/webhook.go`
    # is a production package, and skipping it would hide real routes.
    # `tests` precedes `test` so dropping the trailing slash later
    # cannot let `test` swallow `tests`.
    GO_TEST_DIR_RE = %r{/(?:tests|test|e2e)/}

    # Scan-base-relative, rooted or not. A project whose own base
    # directory is named `test` does not match: that name is not part
    # of the relative path.
    def self.go_test_dir?(relative_path : String) : Bool
      rooted = relative_path.starts_with?('/') ? relative_path : "/#{relative_path}"
      rooted.matches?(GO_TEST_DIR_RE)
    end

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
    # routes the framework ships. `go help packages` ignores a
    # directory named `testdata` the same way: swaggo/swag parks
    # 196 parser-input endpoints under `testdata/...`.
    #
    # `go_test_dir?` covers the conventional trees above, which the
    # toolchain does not ignore.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. Go's toolchain rule is relative to the
    # module, so on an absolute path a single `_`-prefixed directory
    # anywhere above the scan base — `~/_work/repo` on a self-hosted CI
    # runner — excluded every `.go` file in the project.
    #
    # `relative_path` from `base_relative_path` is `/`-rooted, so `"/_"`
    # is exactly "a path segment starts with `_`" without the per-call
    # `split` allocation. The leading-`_` and `testdata/` checks cover a
    # caller that passes an unrooted relative path.
    def self.go_test_file?(relative_path : String) : Bool
      return true if relative_path.ends_with?("_test.go")
      return true if relative_path.starts_with?("testdata/") || relative_path.includes?("/testdata/")
      return true if relative_path.starts_with?('_') || relative_path.includes?("/_")
      go_test_dir?(relative_path)
    end

    include GoTestPath

    # Blanks out `//` line comments and `/* */` block comments, replacing
    # them with spaces so every real line number stays put for PathInfo
    # reporting. Without this a commented-out call reads as a live one —
    # a `// serveCmd.Flags().StringVar(&tok, "secret-token", ...)` note
    # registered a flag that the binary does not accept.
    #
    # All three Go string forms are tracked so a `//` or `/*` inside a
    # literal is never read as a comment opener: interpreted strings
    # (`"..."`, backslash escapes), rune literals (`'.'`), and raw
    # strings (`` `...` ``) — the last take no escapes and may span
    # newlines, hence `raw_quotes`.
    def self.strip_comments(text : String) : String
      Noir::CComments.strip(text, raw_quotes: "`", leak_unterminated_tail: true)
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
    # pre-pass to files that import the framework, plus wiring files that
    # declare a path group without that import (`r := router.New();
    # v1 := r.Group("/api")` — the echo/gin import lives in `router`, so
    # the marker check used to skip `main.go` and every builder handed
    # `v1` was emitted unprefixed). Files that merely mention `.Group(`
    # without a path literal stay out: parsing every `.go` file in a
    # mixed repo is the cost this filter exists to avoid. Route emission
    # is not decided here. `framework_route_source_candidate?` still
    # requires the framework import (or a package that has one), so a
    # non-framework `.Group("/x")` does not become an endpoint.
    # `file_contents` is still populated for every file so the per-file
    # route pass and callee pre-pass keep their read cache.
    def collect_package_groups_ts(group_method : String = "Group", import_marker : (String | Array(String))? = nil, string_seed : Hash(String, String)? = nil) : Tuple(Hash(String, Hash(String, String)), Hash(String, String))
      package_groups = Hash(String, Hash(String, String)).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents = Hash(String, String).new

      get_files_by_extension(".go").each do |path|
        next if go_test_path?(path)
        dir = File.dirname(path)
        files_by_dir[dir] ||= [] of String
        files_by_dir[dir] << path
      end

      files_by_dir.each do |_dir, paths|
        paths.each do |path|
          file_contents[path] = read_file_content(path)
        rescue IO::Error
          # skip
        end
      end

      relevant_by_dir = Hash(String, Array(String)).new
      files_by_dir.each do |dir, paths|
        relevant_by_dir[dir] = if import_marker
                                 markers = import_markers(import_marker)
                                 paths.select do |p|
                                   (c = file_contents[p]?) && (markers.any? { |marker| c.includes?(marker) } || group_decl_file?(c, group_method))
                                 end
                               else
                                 paths
                               end
      end

      # Every relevant file's own-file parse, done up front on the worker
      # threads: it is a pure function of the source, and it is the bulk of
      # this pre-pass. The package logic below consumes the results in the
      # same order it always did; a file whose parse came back nil (it
      # raised on the pool) is parsed again inline, where it behaves as
      # before.
      parse_paths = relevant_by_dir.values.flatten.select { |p| file_contents.has_key?(p) }
      parsed = Noir::WorkerThreads.map(parse_paths) do |p|
        Noir::TreeSitterGoRouteExtractor.extract_engine_names_and_groups(file_contents[p], group_method, string_seed: string_seed)
      end
      engine_names_and_groups = Hash(String, Tuple(Set(String), Hash(String, String))).new
      parse_paths.each_with_index do |p, i|
        if result = parsed[i]
          engine_names_and_groups[p] = result
        end
      end

      files_by_dir.each do |dir, _paths|
        relevant = relevant_by_dir[dir]
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
          names, own = engine_names_and_groups[path]? ||
                       Noir::TreeSitterGoRouteExtractor.extract_engine_names_and_groups(content, group_method, string_seed: string_seed)
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
              found = Noir::TreeSitterGoRouteExtractor.extract_groups(content, groups, group_method, string_seed: string_seed)
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

    # A wiring file's `v1 := e.Group("/api")` (or the raw-string form),
    # checked without a regex so the per-file gate does not recompile
    # one. The call and a path literal both have to be present; they are
    # not required to be adjacent, so a group split across lines still
    # counts. `.Group(fn)` middleware wrappers have no path literal and
    # stay out. This only admits the file to the group pre-pass.
    private def group_decl_file?(content : String, group_method : String) : Bool
      return false unless content.includes?(".#{group_method}(")
      content.includes?("\"/") || content.includes?("`/")
    end

    # Returns the cross-file group map for the given directory, or an
    # empty map when the directory has no registered groups.
    def ts_groups_for_directory(package_groups : Hash(String, Hash(String, String)), dir : String) : Hash(String, String)
      package_groups[dir]? || Hash(String, String).new
    end

    # Per package directory, the struct fields declared with one of the
    # router `types` ({import path => type names}, `/vN` major-version
    # segments ignored): `router *gin.Engine`, `v1 gin.IRouter`, an embedded
    # `*echo.Echo` (named `Echo`). Passed to the extractor as
    # `router_fields`, so `s.router.GET(...)` is a route whatever the field
    # is called. The qualifier is resolved through the declaring file's
    # imports, so an aliased import counts and an unrelated `gin` package
    # does not. A name the package also declares with another type is
    # dropped.
    # ponytail: keyed by field name per package, not per struct, and a
    # same-named field of another type is only seen in files that also
    # declare a router field; resolve the receiver's struct type if that
    # admits a look-alike call.
    #
    # A struct embedding a struct of another scanned package (`type
    # Controller struct{ *core.Controller }`, the qualifier resolved through
    # `import_dirs`) gets that struct's router fields, so `c.Echo.GET(...)`
    # counts in the embedding package. A field's group prefix is read only
    # where the group map already reads it (`s.api = s.router.Group("/v1")`
    # in the using package); one set in another package's constructor
    # (`Group: e.Group("/api/v2")`) is not, and its routes stay unprefixed,
    # as an unread group's do.
    # ponytail: one level of cross-package embedding; walk the embedded
    # struct's own embeddings if a deeper chain turns up.
    #
    # Accessors are the parameterless functions and methods declared to
    # return one of the types (`func V1() *gin.RouterGroup`), per declaring
    # package, with the prefix of the group they return when every `return`
    # names one `package_groups` knows (`return v1` after `v1 =
    # router.Group("/api/v1")`), else "" (the routes stay unprefixed, as on
    # an unread group). See `file_router_receivers`.
    record RouterReceivers, fields : Hash(String, Set(String)), accessors : Hash(String, Hash(String, String)),
      import_dirs : Hash(String, String)

    def package_router_fields(file_contents : Hash(String, String), types : Hash(String, Array(String)),
                              import_dirs : Hash(String, String), package_groups : Hash(String, Hash(String, String))) : RouterReceivers
      routers = Hash(String, Set(String)).new
      others = Hash(String, Set(String)).new
      # dir -> struct name -> its router fields, for embedding packages.
      struct_routers = Hash(String, Hash(String, Array(String))).new
      accessors = Hash(String, Hash(String, String)).new
      # A line that declares a field of one of the types (`router *gin.Engine`,
      # `struct{ *echo.Echo }`), or a function returning one: only those
      # files are parsed.
      names = types.values.flatten.uniq!.map { |t| Regex.escape(t) }.join('|')
      gate = Regex.new("(?:^|[{;])[ \\t]*(?:\\w+(?:[ \\t]*,[ \\t]*\\w+)*[ \\t]+)?\\*?\\w+\\.(?:#{names})[ \\t]*(?:`|//|}|\\r?$)", Regex::Options::MULTILINE)
      returns_gate = Regex.new("^func\\b[^\\n]*\\)[ \\t]*\\*?\\w+\\.(?:#{names})[ \\t]*\\{", Regex::Options::MULTILINE)
      file_contents.each do |path, content|
        next if go_test_path?(path)
        next unless types.each_key.any? { |imp| content.includes?(imp) }
        declares = content.includes?("struct") && content.matches?(gate)
        returns = content.matches?(returns_gate)
        next unless declares || returns
        aliases = Noir::GoCalleeExtractor.extract_import_aliases(content)
        dir = File.dirname(path)
        if declares
          Noir::GoStructFields.collect(content).each do |struct_name, fields|
            fields.each do |field|
              router = router_type?(field.type, aliases, types)
              name = field.embedded ? field.type.split('[').first.rpartition('.').last : field.name
              ((router ? routers : others)[dir] ||= Set(String).new) << name
              ((struct_routers[dir] ||= Hash(String, Array(String)).new)[struct_name] ||= [] of String) << name if router
            end
          end
        end
        next unless returns
        Noir::TreeSitterGoRouteExtractor.router_accessors(content).each do |accessor|
          next unless router_type?(accessor.result, aliases, types)
          prefix = accessor.returns.try { |name| package_groups[dir]?.try(&.[name]?) } || ""
          (accessors[dir] ||= Hash(String, String).new)["#{accessor.method ? "." : ""}#{accessor.name}()"] = prefix
        end
      end
      embedded_router_fields(file_contents, struct_routers, import_dirs, routers) unless struct_routers.empty? || import_dirs.empty?
      routers.each { |dir, found| others[dir]?.try { |o| found.subtract(o) } }
      RouterReceivers.new(routers, accessors, import_dirs)
    end

    # Whether `type_text` (`*gin.Engine`, `gin.IRouter`) names one of the
    # router `types` through the file's import `aliases`.
    private def router_type?(type_text : String, aliases : Hash(String, String), types : Hash(String, Array(String))) : Bool
      qualifier, _, type_name = type_text.strip.lchop('*').split('[').first.rpartition('.')
      import_path = aliases[qualifier]?.try(&.gsub(/\/v\d+(?=\/|\z)/, ""))
      !!(import_path && types[import_path]?.try(&.includes?(type_name)))
    end

    # Adds to `routers` the router fields of structs another package embeds
    # (`*core.Controller`), read from `struct_routers`.
    private def embedded_router_fields(file_contents : Hash(String, String), struct_routers : Hash(String, Hash(String, Array(String))),
                                       import_dirs : Hash(String, String), routers : Hash(String, Set(String)))
      struct_names = struct_routers.values.flat_map(&.keys).uniq!
      file_contents.each do |path, content|
        next if go_test_path?(path)
        next unless content.includes?("struct") && struct_names.any? { |name| content.includes?(".#{name}") }
        aliases = nil
        dir = File.dirname(path)
        Noir::GoStructFields.collect(content).each_value do |fields|
          fields.each do |field|
            next unless field.embedded
            qualifier, _, type_name = field.type.rpartition('.')
            next if qualifier.empty?
            aliases ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
            embedded_dir = aliases[qualifier]?.try { |imp| import_dirs[imp]? }
            next if embedded_dir.nil? || embedded_dir == dir
            struct_routers[embedded_dir]?.try(&.[type_name]?).try { |found| (routers[dir] ||= Set(String).new).concat(found) }
          end
        end
      end
    end

    # The router receivers the file at `path` can name: its package's
    # router fields, plus the accessor calls it can make, keyed as the
    # extractor matches them (see `TreeSitterGoRouteExtractor#
    # accessor_call_info`): `V1()` and `.V1()` (a method) in the declaring
    # package, `router.V1()` through the file's import of it. Returned with
    # `groups` extended by each accessor's known prefix.
    def file_router_receivers(receivers : RouterReceivers, path : String, content : String,
                              groups : Hash(String, String)) : Tuple(Set(String), Hash(String, String))
      dir = File.dirname(path)
      fields = receivers.fields[dir]? || Set(String).new
      return {fields, groups} if receivers.accessors.empty? || !content.includes?("()")
      calls = receivers.accessors[dir]?.try(&.dup) || Hash(String, String).new
      aliases = nil
      receivers.accessors.each do |accessor_dir, found|
        next if accessor_dir == dir
        exported = found.reject { |key, _| key.starts_with?('.') }
        next unless exported.each_key.any? { |key| content.includes?(".#{key}") }
        aliases ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
        aliases.each do |name, import_path|
          next unless receivers.import_dirs[import_path]? == accessor_dir
          exported.each { |key, prefix| calls["#{name}.#{key}"] = prefix }
        end
      end
      return {fields, groups} if calls.empty?
      known = calls.reject { |_, prefix| prefix.empty? }
      {fields + calls.keys.to_set, known.empty? ? groups : groups.merge(known)}
    end

    # Project-wide string facts a route or group path can be built from:
    # other packages' exported string constants (`config.ApiUri`) and
    # one-string wrappers read from their definitions (`conf.BaseUri("/s")`),
    # see `TreeSitterGoRouteExtractor#extract_string_exports`. A name two
    # files define differently is left out. Pass the result as `string_seed`.
    def go_string_seed : Hash(String, String)
      sources = get_files_by_extension(".go").compact_map do |path|
        next if go_test_path?(path)
        content = read_file_content(path)
        content if content.matches?(Noir::TreeSitterGoRouteExtractor::WRAPPER_SIGNATURE) ||
                   content.matches?(Noir::TreeSitterGoRouteExtractor::EXPORTED_STRING_CONST)
      rescue IO::Error
        nil
      end
      exports = Noir::WorkerThreads.map(sources) do |source|
        Noir::TreeSitterGoRouteExtractor.extract_string_exports(source)
      end
      merged = Hash(String, String?).new
      conflicts = Set(String).new
      exports.each do |file_exports|
        file_exports.try &.each do |name, value|
          if merged.has_key?(name) && merged[name] != value
            conflicts << name
          else
            merged[name] = value
          end
        end
      end
      seed = Hash(String, String).new
      merged.each { |name, value| seed[name] = value if value && !conflicts.includes?(name) }
      seed
    end

    # The names a Go file declares with a top-level `var`: `var x ...` and
    # each line of a `var (` block, both written from column 0 as gofmt
    # leaves them.
    private def package_var_names(content : String, names : Set(String))
      in_block = false
      content.each_line do |line|
        if in_block
          if line.starts_with?(')')
            in_block = false
          elsif m = line.match(/\A\s+(\w+)/)
            names << m[1]
          end
        elsif line.starts_with?("var")
          if line.matches?(/\Avar\s*\(\s*(?:\/\/.*)?\z/)
            in_block = true
          elsif m = line.match(/\Avar\s+(\w+)/)
            names << m[1]
          end
        end
      end
    end

    # Router-builder helpers (`func addUserRoutes(rg *gin.RouterGroup)`)
    # receive their group as an argument, so the prefix lives at the call
    # site (`addUserRoutes(router.Group("/v1"))`) and has to be grafted onto
    # the helper's routes. `builder_type` is the group parameter type as
    # written (`*gin.RouterGroup`, `*echo.Group`, `*route.RouterGroup`); its
    # text gates the per-file parse and its last segment is the type name.
    #
    # Builds `{dir => {builder_fn => set(prefixes)}}` by (1) collecting
    # every helper across the directory's files and (2) resolving each call
    # site `F(arg)` to the prefix `arg` denotes via the caller's directory
    # group map. A call from another package (`routes.F(api)`) counts when
    # the caller imports the helper's package; a method call (`h.Register(v1)`,
    # the qualifier not an import alias) resolves to a helper of that name in
    # the caller's package or one it imports. A helper called with several
    # groups accumulates each prefix; one with any unresolved call site (the
    # root router, a computed value) is left out so the whole-file pass
    # keeps its routes.
    def resolve_router_builder_prefixes(file_contents : Hash(String, String),
                                        package_groups : Hash(String, Hash(String, String)),
                                        builder_type : String) : Hash(String, Hash(String, Set(String)))
      type_name = builder_type.split('.').last
      result = Hash(String, Hash(String, Set(String))).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents.each_key { |p| (files_by_dir[File.dirname(p)] ||= [] of String) << p }

      builders_by_dir = Hash(String, Set(String)).new
      file_builders = Hash(String, Hash(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder)).new
      files_by_dir.each do |dir, paths|
        builders = Set(String).new
        duplicates = Set(String).new
        paths.each do |p|
          content = file_contents[p]?
          next unless content && content.includes?(builder_type)
          (file_builders[p] = Noir::TreeSitterGoRouteExtractor.collect_router_group_builders(content, type_name)).each_key do |fn|
            # Only methods can share a name across a package's files; such a
            # name is ambiguous at a `h.Register(g)` call site.
            duplicates << fn unless builders.add?(fn)
          end
        end
        builders.subtract(duplicates)
        builders_by_dir[dir] = builders unless builders.empty?
      end
      return result if builders_by_dir.empty?

      # Import path of each builder package, for cross-package call sites.
      builder_imports = Hash(String, String).new
      modules = collect_go_modules
      builders_by_dir.each_key do |dir|
        if import_path = import_path_for_dir(dir, modules)
          builder_imports[import_path] = dir
        end
      end

      # `slice = append(slice, builderA, builderB)` across the package's
      # files, for a slice the package declares at its top level.
      slices_by_dir = Hash(String, Hash(String, Array(String))).new
      builders_by_dir.each do |dir, builders|
        package_vars = Set(String).new
        appends = Hash(String, Array(String)).new
        files_by_dir[dir].each do |p|
          content = file_contents[p]? || next
          package_var_names(content, package_vars) if content.includes?("var")
          next unless content.includes?("append(")
          Noir::TreeSitterGoRouteExtractor.collect_builder_slice_appends(content, builders).each do |slice, names|
            (appends[slice] ||= [] of String).concat(names)
          end
        end
        appends.select! { |slice, _| package_vars.includes?(slice) }
        slices_by_dir[dir] = appends unless appends.empty?
      end

      prefixes_by_dir = Hash(String, Hash(String, Set(String))).new
      unresolved_by_dir = Hash(String, Set(String)).new
      # A call made inside another builder that hands on its own parameter
      # (vikunja's `registerAPIRoutesV2(e, a)` calling `m.Register(a)`): the
      # argument is whatever that builder was handed, not a package group
      # of the same name. {target dir, fn, caller's dir, caller builder,
      # the by-name prefix used when the caller never resolves}.
      handed = [] of {String, String, String, String, String?}
      files_by_dir.each do |dir, paths|
        group_map = package_groups[dir]? || Hash(String, String).new
        paths.each do |p|
          content = file_contents[p]?
          next unless content
          names = builders_by_dir[dir]?.try(&.dup) || Set(String).new
          # Quoted, so `"app/routes"` is not matched by `"app/routes/admin"`.
          imported = builder_imports.select { |import_path, _| content.includes?(%("#{import_path}")) }
          imported.each_value { |d| names.concat(builders_by_dir[d]) }
          next if names.empty?
          aliases = nil
          own_builders = file_builders[p]?
          slices = slices_by_dir[dir]? || Hash(String, Array(String)).new
          Noir::TreeSitterGoRouteExtractor.collect_router_builder_callsites(content, names, group_map, slices).each do |fn, arg, qualifier, row|
            local = dir if builders_by_dir[dir]?.try(&.includes?(fn))
            target = if qualifier.empty?
                       local
                     else
                       aliases ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
                       if import_path = aliases[qualifier]?
                         d = imported[import_path]?
                         d if d && builders_by_dir[d].includes?(fn)
                       else
                         # The receiver's type is unknown: resolve only a name
                         # exactly one candidate package declares.
                         candidates = imported.values.select { |d| builders_by_dir[d].includes?(fn) }
                         candidates << local if local
                         candidates.uniq!
                         candidates.first if candidates.size == 1
                       end
                     end
            next unless target
            if (enclosing = own_builders.try &.find { |_, rb| rb.param == arg && rb.start_row <= row <= rb.end_row }) &&
               builders_by_dir[dir]?.try(&.includes?(enclosing[0]))
              handed << {target, fn, dir, enclosing[0], group_map[arg]?}
              next
            end
            prefix = group_map[arg]?
            prefix = arg if prefix.nil? && arg.starts_with?("/")
            if prefix
              ((prefixes_by_dir[target] ||= Hash(String, Set(String)).new)[fn] ||= Set(String).new) << prefix
            else
              (unresolved_by_dir[target] ||= Set(String).new) << fn
            end
          end
        end
      end

      # Through chains of builders: a caller settles once every call handing
      # it a group has. One whose call sites never resolve falls back to the
      # argument's name, as a call outside any builder does.
      settled = Set({String, String, String, String, String?}).new
      (handed.size + 1).times do
        progressed = false
        handed.each do |dep|
          next if settled.includes?(dep)
          target, fn, from_dir, from_fn, _ = dep
          next if unresolved_by_dir[from_dir]?.try(&.includes?(from_fn))
          next if handed.any? { |other| !settled.includes?(other) && other[0] == from_dir && other[1] == from_fn }
          from = prefixes_by_dir[from_dir]?.try(&.[from_fn]?) || next
          ((prefixes_by_dir[target] ||= Hash(String, Set(String)).new)[fn] ||= Set(String).new).concat(from)
          settled << dep
          progressed = true
        end
        break unless progressed
      end
      handed.each do |dep|
        next if settled.includes?(dep)
        target, fn, _, _, by_name = dep
        if by_name
          ((prefixes_by_dir[target] ||= Hash(String, Set(String)).new)[fn] ||= Set(String).new) << by_name
        else
          (unresolved_by_dir[target] ||= Set(String).new) << fn
        end
      end

      prefixes_by_dir.each do |dir, prefixes|
        unresolved = unresolved_by_dir[dir]?
        prefixes.reject! { |fn, _| unresolved.includes?(fn) } if unresolved
        result[dir] = prefixes unless prefixes.empty?
      end
      result
    end

    # The router-builder helpers defined in `content` to expand, with their
    # resolved call-site prefixes. A helper whose group parameter name is
    # also a package-level group (both named `v1`) is resolved by the
    # whole-file pass by that name, so it is left alone only when its call
    # sites hand it that same prefix. vikunja's `registerAPIRoutesV2(e, a2)`
    # names its parameter `a` too, but is handed `/api/v2`, not the `/api/v1`
    # of `RegisterRoutes`' `a`: the name is the parameter's, scoped to the
    # helper.
    def router_builder_expansions(content : String,
                                  builder_type : String,
                                  dir_prefixes : Hash(String, Set(String))?,
                                  cross_file_groups : Hash(String, String)) : Array(Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String)))
      expansions = [] of Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String))
      return expansions unless dir_prefixes && content.includes?(builder_type)
      Noir::TreeSitterGoRouteExtractor.collect_router_group_builders(content, builder_type.split('.').last).each do |fn, rb|
        pset = dir_prefixes[fn]?
        next if pset.nil? || pset.empty?
        next if (shadowed = cross_file_groups[rb.param]?) && pset == Set{shadowed}
        expansions << {fn, rb, pset}
      end
      expansions
    end

    # A struct type that embeds the framework's router (`type Admin struct {
    # fiber.Router }`), the package it is declared in, and the prefix of the
    # one group it is ever built from.
    record RouterWrapper, dir : String, type_name : String, import_path : String?, prefix : String

    DOT_IMPORT = /^\s*(?:import\s+)?\.\s+"/m

    # Router groups handed out wrapped in a project type, uber/fx style:
    # `CreateEndpointGroups` returns `&Admin{Router: admin}` with `admin :=
    # app.Group("/api/admin", mw)`, and `func RegisterAdmin(admin *svr.Admin,
    # ...)` registers on it. fx calls `RegisterAdmin`, so there is no call
    # site handing it a group: the link is the parameter's type.
    #
    # A wrapper counts only when all of these hold, else its routes keep
    # today's (unprefixed) reading:
    #   * it embeds `builder_type` (a named `R fiber.Router` field is reached
    #     as `admin.R.Get`, which no builder reads);
    #   * no other wrapper of that name is declared in the scan, and its
    #     package declares no other type of that name (read by text, so a
    #     build-tagged twin or a same-named nested field type also counts).
    #     A same-named type of another package (`service.Admin`) is told
    #     apart by the import path its qualifier names;
    #   * the scan constructs it exactly once, as a literal whose router
    #     field names a group its function builds off a root router (see
    #     `TreeSitterGoRouteExtractor#collect_router_wrapper_constructions`).
    #     A second literal, a `new(Admin)`, or a literal whose router value is
    #     not read (a parameter, the root itself, a call) drops it.
    # Not read (the routes stay unprefixed): a router assigned to the field
    # after construction (`a.Router = g`), a wrapper built by a generic or
    # reflective helper, a type alias (`type Admin = fiber.Router`), a group
    # variable bound more than once in the constructing function (`admin =
    # app.Group("/b")` after the literal: which binding it saw is not read), and
    # routes registered on the wrapper as a method receiver (`func (a *Admin)
    # Routes()`) rather than a parameter.
    def resolve_router_wrappers(file_contents : Hash(String, String), builder_type : String) : Array(RouterWrapper)
      field = builder_type.split('.').last
      decls = Hash(String, Array({String, Bool})).new
      file_contents.each do |path, content|
        next unless content.includes?(builder_type)
        Noir::GoStructFields.collect(content).each do |name, fields|
          next unless fields.any? { |f| f.embedded && f.type == builder_type }
          (decls[name] ||= [] of {String, Bool}) << {File.dirname(path), fields.size == 1}
        end
      end
      return [] of RouterWrapper if decls.empty?
      decls.select! do |name, found|
        next false unless found.size == 1
        decl = /^\s*(?:type\s+)?#{Regex.escape(name)}\s+(?:struct|interface)\b|\btype\s+#{Regex.escape(name)}\b/m
        file_contents.sum do |path, content|
          File.dirname(path) == found[0][0] && content.includes?(name) ? content.scan(decl).size : 0
        end == 1
      end
      return [] of RouterWrapper if decls.empty?

      modules = collect_go_modules
      imports = decls.transform_values { |found| import_path_for_dir(found[0][0], modules) }
      types = decls.transform_values { |found| found[0][1] }
      constructions = Hash(String, Array(String?)).new
      file_contents.each do |path, content|
        next unless types.each_key.any? { |name| content.includes?(name) }
        dir = File.dirname(path)
        aliases = nil
        Noir::TreeSitterGoRouteExtractor.collect_router_wrapper_constructions(content, types, field).each do |built|
          # A same-named type of another package (`service.Admin`) is not
          # this one. A qualifier no import explains, or a bare name in a
          # package that dot-imports, may be: it counts, as a construction
          # the prefix was not read from when it is.
          own = if built.qualifier.empty?
                  dir == decls[built.type_name][0][0] || DOT_IMPORT.matches?(content)
                else
                  aliases ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
                  imported = aliases[built.qualifier]?
                  imported.nil? || imported == imports[built.type_name]
                end
          (constructions[built.type_name] ||= [] of String?) << built.prefix if own
        end
      end
      constructions.compact_map do |name, prefixes|
        prefix = prefixes.first if prefixes.size == 1
        RouterWrapper.new(decls[name][0][0], name, imports[name], prefix) if prefix
      end
    end

    # The functions in `content` that take one of `wrappers` as their router
    # parameter (`admin *svr.Admin`, or `admin *Admin` in the wrapper's own
    # package), as router-builder expansions bound to the wrapper's prefix.
    # A function `taken` already expands, or that takes two wrappers, is left
    # alone: its body would be read once per binding.
    def router_wrapper_expansions(content : String, path : String, wrappers : Array(RouterWrapper),
                                  taken : Array(Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String)))) : Array(Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String)))
      expansions = [] of Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String))
      dir = File.dirname(path)
      aliases = nil
      wrappers.each do |wrapper|
        next unless content.includes?(wrapper.type_name)
        qualifier = if dir == wrapper.dir
                      ""
                    else
                      aliases ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
                      aliases.key_for?(wrapper.import_path) if wrapper.import_path
                    end
        next unless qualifier
        Noir::TreeSitterGoRouteExtractor.collect_router_group_builders(content, wrapper.type_name, qualifier).each do |fn, rb|
          expansions << {fn, rb, Set{wrapper.prefix}}
        end
      end
      starts = (expansions + taken).map { |_, rb, _| rb.start_row }
      expansions.reject { |_, rb, _| starts.count(rb.start_row) > 1 }
    end

    # Emits every `expansions` helper's routes once per call-site prefix
    # (with the route's callees), then yields each `(line, endpoint)` pair
    # of the helper body so the caller applies its framework's param
    # patterns. The caller skips the helper bodies in its own line loop.
    # Endpoints go to `into` (default: `result`).
    def expand_router_builders(content : String,
                               lines : Array(String),
                               path : String,
                               expansions : Array(Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String))),
                               callees_by_route : Hash(Int32, Array(Tuple(String, String, Int32))),
                               named : Noir::GoNamedHandler?,
                               handle_method : String? = nil,
                               into emitted_to : Array(Endpoint) = result,
                               string_seed : Hash(String, String)? = nil,
                               group_method : String = "Group",
                               handlefunc_methods : Bool = false,
                               literal_join : Bool = false,
                               & : String, Endpoint ->)
      expansions.each do |fn, rb, pset|
        emitted = [] of Endpoint
        pset.each do |prefix|
          Noir::TreeSitterGoRouteExtractor.extract_routes_from_function(
            content, fn, {rb.param => prefix}, handle_method: handle_method, string_seed: string_seed,
            group_method: group_method, handlefunc_methods: handlefunc_methods, literal_join: literal_join
          ).each do |route|
            details = Details.new(PathInfo.new(path, route.line + 1))
            Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
              ep = Endpoint.new(route.path, verb, details)
              # mux's `.Queries("type", "{type}")` declares required query params.
              route.query_params.each { |qp| ep.params << Param.new(qp, "", "query") }
              ep.handler = named.handler_for(route) if named
              callees_by_route[route.line]?.try &.each do |name, callee_path, callee_line|
                ep.push_callee(Callee.new(name, path: callee_path, line: callee_line))
              end
              emitted_to << ep
              named.try &.bind(route, ep)
              emitted << ep
            end
          end
        end
        each_router_builder_line(lines, emitted, rb) do |line, eps|
          eps.each { |ep| yield line, ep }
        end
      end
    end

    # Yields each line of a router-builder body that belongs to one of the
    # expanded `emitted` endpoints (the registration line and its inline
    # closure) with the endpoints registered there.
    private def each_router_builder_line(lines : Array(String),
                                         emitted : Array(Endpoint),
                                         builder : Noir::TreeSitterGoRouteExtractor::RouterBuilder,
                                         & : String, Array(Endpoint) ->)
      eps_by_line = Hash(Int32, Array(Endpoint)).new { |h, k| h[k] = [] of Endpoint }
      emitted.each do |ep|
        ep.details.code_paths.each do |cp|
          if ln = cp.line
            eps_by_line[ln.to_i - 1] << ep
          end
        end
      end
      return if eps_by_line.empty?
      currents = [] of Endpoint
      in_inline = false
      brace_count = 0
      (builder.start_row..[builder.end_row, lines.size - 1].min).each do |i|
        line = lines[i]?
        next unless line
        apply_now = false
        if eps = eps_by_line[i]?
          currents = eps
          apply_now = true
          if line.includes?("func(")
            in_inline = true
            brace_count = line.count("{") - line.count("}")
            if brace_count <= 0
              in_inline = false
              brace_count = 0
            end
          end
        elsif in_inline
          brace_count += line.count("{") - line.count("}")
          if brace_count <= 0
            in_inline = false
            brace_count = 0
          end
          apply_now = true
        end
        yield line, currents if !currents.empty? && apply_now
      end
    end

    GO_HTTP_ROUTE_CALL_RE = /\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|QUERY|Get|Post|Put|Delete|Patch|Head|Options|Query|ANY|Any|All)\s*\(/

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the per-framework extra route methods are
    # a small fixed set per analyzer, so memoize their matchers per name
    # instead of rebuilding them for every candidate file.
    @extra_method_regexes = Hash(String, Regex).new

    # One compiled matcher per framework import marker set. Each analyzer
    # passes a single `IMPORT_MARKER` constant, so the cardinality here is
    # one entry; the Hash just keeps the memo honest if that changes.
    @import_marker_regexes = Hash(String, Regex).new

    # An analyzer may name more than one import path when a framework is
    # shipped under several of them — a maintained hard fork exposing the
    # same routing API, for instance. Callers keep passing a plain String.
    private def import_markers(import_marker : String | Array(String)) : Array(String)
      import_marker.is_a?(String) ? [import_marker] : import_marker
    end

    # Called once per candidate file, so the single-marker case reuses the
    # constant itself as the memo key rather than allocating a joined one.
    private def import_marker_regex(import_marker : String | Array(String)) : Regex
      key = import_marker.is_a?(String) ? import_marker : import_marker.join('\n')
      @import_marker_regexes[key] ||= Regex.union(import_markers(import_marker))
    end

    # Per-package directories that import a target framework. Some real
    # projects hide the concrete framework type behind a local interface, so
    # the file that calls `router.GET(...)` may not import Gin/Echo itself.
    def framework_package_dirs(file_contents : Hash(String, String), import_marker : String | Array(String)) : Set(String)
      dirs = Set(String).new
      marker = import_marker_regex(import_marker)
      file_contents.each do |path, content|
        dirs << File.dirname(path) if content_matches?(content, marker)
      end
      dirs
    end

    # Cheap gate before the tree-sitter route pass. Handler-only files often
    # import Gin/Echo for `*gin.Context` / `echo.Context`, but they cannot emit
    # endpoints unless they contain a route/static registration call.
    #
    # `verb_calls: false` drops the shared `.GET(` / `.Get(` gate for a
    # framework that registers no routes through verb-named methods
    # (gorilla/mux: `Router.Get(name)` *looks up* a named route). In a
    # package that imports the framework, `.Get(` / `.Put(` on caches,
    # maps and clients otherwise sends nearly every file to the parser.
    def go_route_source_candidate?(content : String, extra_methods : Array(String), verb_calls : Bool = true) : Bool
      return true if verb_calls && content_matches?(content, GO_HTTP_ROUTE_CALL_RE)
      extra_methods.any? do |method|
        method_regex = @extra_method_regexes[method] ||= /\.#{Regex.escape(method)}\s*\(/
        content_matches?(content, method_regex)
      end
    end

    # Runs `extract` for every file the route pass will parse — the same
    # test-file and `framework_route_source_candidate?` gates, evaluated here
    # on the analyzer's own fiber — on `Noir::WorkerThreads`, and returns
    # the results by path.
    #
    # `extract` must be pure: tree-sitter extraction over the file's source
    # and read-only tables built before this call. The route pass then
    # takes each file's result from here instead of parsing it itself, and
    # parses inline for any file missing (a gate it evaluates differently,
    # or an extraction that raised on the pool) — so what the pass emits,
    # and in what order, is unchanged.
    def prefetch_route_sources(file_contents : Hash(String, String),
                               framework_dirs : Set(String),
                               import_marker : String | Array(String),
                               extra_methods : Array(String),
                               verb_calls : Bool = true,
                               &extract : String, String -> T) : Hash(String, T) forall T
      candidates = get_files_by_extension(".go").select do |path|
        next false if go_test_path?(path)
        content = file_contents[path]?
        next false if content.nil?
        framework_route_source_candidate?(content, File.dirname(path), framework_dirs, import_marker, extra_methods, verb_calls)
      end
      prefetch_sources(candidates, file_contents, &extract)
    end

    # `extract` for each of `paths` (all keys of `file_contents`) on
    # `Noir::WorkerThreads`, by path; a path whose extraction raised is
    # left out, so the caller computes it inline as before.
    def prefetch_sources(paths : Array(String), file_contents : Hash(String, String),
                         &extract : String, String -> T) : Hash(String, T) forall T
      results = Noir::WorkerThreads.map(paths) { |path| extract.call(path, file_contents[path]) }
      prefetched = Hash(String, T).new
      paths.each_with_index do |path, index|
        if result = results[index]
          prefetched[path] = result
        end
      end
      prefetched
    end

    def framework_route_source_candidate?(content : String,
                                          dir : String,
                                          framework_dirs : Set(String),
                                          import_marker : String | Array(String),
                                          extra_methods : Array(String),
                                          verb_calls : Bool = true) : Bool
      return false unless content_matches?(content, import_marker_regex(import_marker)) || framework_dirs.includes?(dir)
      go_route_source_candidate?(content, extra_methods, verb_calls)
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

    def ts_function_bodies_for_directory(package_bodies : Noir::GoCalleeExtractor::LazyPackageBodies, dir : String) : Hash(String, Noir::GoCalleeExtractor::FunctionBody)
      package_bodies.functions_for(dir)
    end

    # Per-directory function and method tables, built for a directory only
    # when an analyzer looks it up. Holds exactly what
    # `collect_package_function_bodies` / `collect_package_controller_method_bodies`
    # would store for that directory, and is empty unless callees are
    # requested — see `Noir::GoCalleeExtractor::LazyPackageBodies`. Use it
    # wherever the tables are only read through the `ts_*_for_directory`
    # lookups; the import-path indexes iterate every directory and still
    # need the eager maps.
    def lazy_package_bodies(file_contents : Hash(String, String)) : Noir::GoCalleeExtractor::LazyPackageBodies
      Noir::GoCalleeExtractor.lazy_package_bodies_if(callees_needed?, file_contents)
    end

    # Lookup scope for `Noir::GoNamedHandler`: a named handler declared in
    # another file of the route's package, or in a scanned package it
    # imports (`handlers.List`). Not gated on callees: the handler body is
    # where the route's request params are read. Packages are parsed only
    # when a route names a handler outside its own file.
    def named_handler_scope(file_contents : Hash(String, String)) : Noir::GoNamedHandler::Scope
      import_dirs = Hash(String, String).new
      modules = collect_go_modules
      unless modules.empty?
        file_contents.each_key.map { |path| File.dirname(path) }.to_set.each do |dir|
          if import_path = import_path_for_dir(dir, modules)
            import_dirs[import_path] ||= dir
          end
        end
      end
      Noir::GoNamedHandler.scope(file_contents, import_dirs)
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
      # Cheap gate: a file with controller methods must contain a method
      # receiver. gofmt always writes those as `func (recv Type) Name(`,
      # so files without `func (` can't define controller methods and
      # are skipped before paying for a tree-sitter parse. The parses run
      # on the worker threads; the merge below stays in file order.
      receivers = file_contents.keys.select { |path| file_contents[path].includes?("func (") }
      parsed = prefetch_sources(receivers, file_contents) do |_path, content|
        Noir::TreeSitterGoRouteExtractor.extract_controller_methods(content)
      end
      file_contents.each do |path, content|
        next unless content.includes?("func (")
        methods = parsed[path]? || Noir::TreeSitterGoRouteExtractor.extract_controller_methods(content)
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

    def ts_controller_method_bodies_for_directory(package_bodies : Noir::GoCalleeExtractor::LazyPackageBodies, dir : String) : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))
      package_bodies.methods_for(dir)
    end

    # Read every `.go` file once into a `{path => source}` hash. Used by
    # analyzers (Goyave) that don't otherwise call
    # `collect_package_groups_ts` but still need the file_contents hash
    # as input to `collect_package_function_bodies`.
    def read_package_file_contents : Hash(String, String)
      file_contents = Hash(String, String).new
      get_files_by_extension(".go").each do |path|
        next if go_test_path?(path)
        begin
          file_contents[path] = read_file_content(path)
        rescue IO::Error
          # skip
        end
      end
      file_contents
    end

    # --- Adapter helpers (shared across Go framework adapters) ----------

    def add_param_to_endpoint(param : Param, endpoint : Endpoint)
      if !param.name.empty? && !endpoint.method.empty? && !endpoint.url.empty?
        # Don't re-add an identical (name, type) param. go-zero's
        # handler-body getters (`httpx.ParseForm`, repeated across several
        # handlers in a single-file app) would otherwise stack four
        # `body` params onto one endpoint; the same guard keeps every Go
        # adapter's line-loop from emitting duplicates.
        return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
        endpoint.params << param
      end
    end

    # A handler shared by `/short` and `/short/:word` reads `word` on both,
    # so both get the path parameter; the route without the slot has none.
    # Only that shape is dropped: a sibling route of the same handler that
    # is this URL plus the slot's segment. A route whose prefix noir could
    # not resolve (`Group(s.base)`) has no such sibling and keeps its params.
    # Middleware is not that handler: `GoNamedHandler` credits a middleware
    # path read only to routes whose URL has the slot.
    def self.drop_unslotted_path_params(endpoints : Array(Endpoint)) : Array(Endpoint)
      by_handler = Hash({String, Int32}, Array(Int32)).new
      endpoints.each_with_index do |endpoint, idx|
        handler = endpoint.handler || next
        path = handler.path || next
        line = handler.line || next
        (by_handler[{path, line}] ||= [] of Int32) << idx
      end
      by_handler.each_value do |indexes|
        next if indexes.size < 2
        indexes.each do |idx|
          endpoint = endpoints[idx]
          url = endpoint.url.rchop('/')
          kept = endpoint.params.reject do |param|
            param.param_type == "path" && !path_slot?(endpoint.url, param.name) &&
              indexes.any? do |other|
                sibling = endpoints[other].url
                other != idx && path_slot?(sibling, param.name) &&
                  sibling.split('/').reject { |segment| path_slot?(segment, param.name) }.join('/').rchop('/') == url
              end
          end
          next if kept.size == endpoint.params.size
          endpoint.params = kept
          endpoints[idx] = endpoint
        end
      end
      endpoints
    end

    # Whether `url` has a slot the path parameter `name` reads. The predicate
    # lives on `GoNamedHandler`, which applies it when a middleware body is
    # attributed; this pass uses the same one.
    def self.path_slot?(url : String, name : String) : Bool
      Noir::GoNamedHandler.path_slot?(url, name)
    end

    def static_dir_entry(source_path : String, static_path : String, file_path : String) : Hash(String, String)
      {
        "static_path" => static_path,
        "file_path"   => file_path,
        "source_path" => source_path,
      }
    end

    # A static mount's endpoint set is every file under its directory,
    # images, fonts and SVGs included. Those come from the walk's media list
    # (`CodeLocator#media_files`; the media filter keeps them out of the index);
    # everything else from the index. Both are bounded by the scan base and
    # skip the subtrees and `--exclude-path` entries the walk prunes. A
    # single-file target (`e.File("/robots.txt", "static/robots.txt")`) is
    # matched as is.
    def resolve_public_dirs(public_dirs : Array(Hash(String, String)))
      media_files = CodeLocator.instance.media_files
      public_dirs.each do |p_dir|
        full_path = resolve_public_dir_path(p_dir)
        dir_prefix = full_path.ends_with?("/") ? full_path : "#{full_path}/"
        static_url = p_dir["static_path"].chomp('/')
        get_files_by_prefix(full_path).concat(media_files).each do |path|
          # `get_files_by_prefix` matches any file starting with the prefix
          # ("public" matches "public2"), so require a directory boundary.
          next unless path == full_path || path.starts_with?(dir_prefix)
          result << Endpoint.new("#{static_url}#{path.lchop(full_path)}", "GET", Details.new(PathInfo.new(path)))
        end
      end
    end

    # `File.exists?` alongside `Dir.exists?`, in both branches: the same
    # `public_dirs` list carries single-file static routes
    # (Echo's `e.File("/robots.txt", "static/robots.txt")`) as well as
    # directories. Testing only for a directory made the source-relative
    # branch miss every single-file route, which then fell back to
    # `base_path + file_path` — a path that only exists when the scan base
    # happens to be the Go project root. Scanning the same project from one
    # directory up silently lost the route.
    #
    # `Path.posix`, not `Path[]`: a native Windows `Path` re-joins with `\`,
    # and the result is matched against `/`-separated walk paths below.
    private def resolve_public_dir_path(p_dir : Hash(String, String)) : String
      file_path = p_dir["file_path"]
      return Path.posix(file_path).normalize.to_s if file_path.starts_with?("/") && static_target_exists?(file_path)

      normalized_file_path = file_path.lstrip("/")
      root = base_path
      if source_path = p_dir["source_path"]?
        source_dir = File.dirname(source_path)
        source_relative = Path.posix((source_dir + "/" + normalized_file_path).squeeze('/')).normalize.to_s
        if static_target_exists?(source_relative)
          return preserve_relative_prefix(source_relative, source_path)
        end

        root = base_path_for_path(source_path)
      end

      raw_full_path = (root + "/" + normalized_file_path).squeeze('/')
      normalized_full_path = Path.posix(raw_full_path).normalize.to_s

      if root.starts_with?("./") && !normalized_full_path.starts_with?("./") && !normalized_full_path.starts_with?("/")
        "./#{normalized_full_path}"
      else
        normalized_full_path
      end
    end

    # A static route's target on disk, which may be either a directory
    # (`e.Static`) or a single file (`e.File`). Spelled with both checks
    # rather than the equivalent bare `File.exists?` so the file half is
    # not mistaken for a leftover: `Dir.exists?` alone is what dropped
    # single-file routes.
    private def static_target_exists?(path : String) : Bool
      Dir.exists?(path) || File.exists?(path)
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
      # Basename index instead of a full `file_map` walk: this runs once
      # per Go analyzer, and on a monorepo the `.go` module files are a
      # handful of entries out of tens of thousands. No `File.directory?`
      # either — the detector only registers regular files.
      get_files_by_basename("go.mod").each do |path|
        # Scan-base-relative: a `vendor` directory *above* the base is
        # not this project's vendor tree, and matching it dropped the
        # module map (and with it 13 of the fixture tree's 276
        # endpoints) for any checkout that lived under one.
        next if base_relative_path(path).includes?("/vendor/")

        begin
          content = read_file_content(path)
        rescue IO::Error
          next
        end

        match = content.match(/^\s*module\s+(\S+)/m)
        next unless match
        modules << {match[1], Noir::PathScope.expand(File.dirname(path))}
      end

      modules.sort_by! { |(_module_path, dir)| -dir.size }
      modules
    end

    private def import_path_for_dir(dir : String, modules : Array(Tuple(String, String))) : String?
      expanded_dir = Noir::PathScope.expand(dir)
      modules.each do |module_path, module_dir|
        next unless expanded_dir == module_dir || expanded_dir.starts_with?("#{module_dir}/")

        rel = expanded_dir[module_dir.size..].lstrip("/")
        return rel.empty? ? module_path : "#{module_path}/#{rel}"
      end

      # No go.mod covers this directory. Older trees (and GOPATH-era
      # checkouts) still import packages by their full path
      # (`"github.com/acme/app/controllers"`) while the sources sit at
      # `<scan base>/controllers`. Without a module path, cross-package
      # builder calls (`controllers.RegisterX(api.Group("/products"))`)
      # cannot be tied to the package that declares the builder, and the
      # routes come out unprefixed.
      modless_import_index[expanded_dir]?
    end

    # `{expanded dir => import path}` for packages no go.mod covers.
    # Built once, and only when a lookup misses every module: a tree
    # with a go.mod never pays for it.
    @modless_import_index : Hash(String, String)? = nil

    private def modless_import_index : Hash(String, String)
      @modless_import_index ||= build_modless_import_index
    end

    # The module prefix is the part of an import left after the longest
    # scan-base-relative package path it ends with. The prefix that
    # explains the most packages wins; a tie is left unresolved unless
    # exactly one candidate ends in the scan base's directory name
    # (the usual `github.com/user/<repo>` checkout). Stdlib imports
    # (`net/http`) are not candidates: their first element has no dot,
    # so a local package named `http` is not claimed by them.
    private def build_modless_import_index : Hash(String, String)
      index = Hash(String, String).new
      by_base = Hash(String, Hash(String, String)).new
      imports = Set(String).new

      get_files_by_extension(".go").each do |path|
        next if go_test_path?(path)
        expanded = Noir::PathScope.expand(File.dirname(path))
        base = Noir::PathScope.normalize_root(configured_base_for(path))
        rel = package_rel_under(expanded, base)
        # A vendored tree's import paths are third-party. Package main at
        # the scan root has an empty rel and is not itself an importable
        # package, but its import block is where the local paths are quoted.
        if rel && (rel == "vendor" || rel.starts_with?("vendor/") || rel.includes?("/vendor/"))
          next
        end
        if rel && !rel.empty?
          (by_base[base] ||= Hash(String, String).new)[rel] = expanded
        end
        begin
          content = read_file_content(path)
        rescue IO::Error
          next
        end
        next unless content.includes?("import")
        Noir::GoCalleeExtractor.extract_import_aliases(content).each_value { |import_path| imports << import_path }
      end

      by_base.each do |base, rels|
        rels_longest = rels.keys.sort_by! { |rel| -rel.size }
        votes = Hash(String, Set(String)).new
        imports.each do |import_path|
          rels_longest.each do |rel|
            next unless import_matches_package?(import_path, rel)
            prefix = import_path == rel ? "" : import_path[0, import_path.size - rel.size - 1]
            (votes[prefix] ||= Set(String).new) << rel
            break
          end
        end
        next if votes.empty?

        best = Hash(String, Tuple(String, Int32)).new
        tied = Set(String).new
        votes.each do |prefix, explained|
          score = explained.size
          explained.each do |rel|
            if current = best[rel]?
              if score > current[1]
                best[rel] = {prefix, score}
                tied.delete(rel)
              elsif score == current[1] && prefix != current[0]
                tied << rel
              end
            else
              best[rel] = {prefix, score}
            end
          end
        end

        base_name = File.basename(base)
        best.each do |rel, (prefix, _score)|
          chosen = prefix
          if tied.includes?(rel)
            chosen = modless_tie_break(rel, votes, best[rel][1], base_name)
            next unless chosen
          end
          dir = rels[rel]? || next
          import_path = chosen.empty? ? rel : "#{chosen}/#{rel}"
          index[dir] = import_path if imports.includes?(import_path)
        end
      end
      index
    end

    # The one tied prefix that ends with the scan-base directory name, or
    # nil when the tie is not broken that way.
    private def modless_tie_break(rel : String, votes : Hash(String, Set(String)), score : Int32, base_name : String) : String?
      chosen = nil
      votes.each do |prefix, explained|
        next unless explained.size == score && explained.includes?(rel)
        next unless prefix == base_name || prefix.ends_with?("/#{base_name}")
        return if chosen
        chosen = prefix
      end
      chosen
    end

    private def import_matches_package?(import_path : String, rel : String) : Bool
      return true if import_path == rel
      return false unless import_path.ends_with?("/#{rel}")
      import_path.split('/', 2).first.includes?('.')
    end

    # `dir` relative to `base`, or nil when `dir` is outside `base`.
    # Empty string is the base itself (package main at the module root).
    private def package_rel_under(expanded_dir : String, base : String) : String?
      return "" if expanded_dir == base
      return unless expanded_dir.starts_with?(base) && expanded_dir.byte_at(base.bytesize) == '/'.ord
      expanded_dir[base.bytesize + 1..]
    end
  end
end
