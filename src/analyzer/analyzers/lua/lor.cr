require "../../../models/analyzer"
require "../../../miniparsers/lua_callee_extractor"

module Analyzer::Lua
  # lor (https://github.com/sumory/lor) is an Express-style web framework for
  # Lua on top of OpenResty. Routes are declared on the application or on a
  # router instance:
  #
  #   local app = lor()
  #   app:get("/", handler)                       -- direct app route
  #
  #   local userRouter = lor:Router()
  #   userRouter:get("/find/:id", handler)        -- router route
  #   app:use("/user", userRouter())              -- mount router under a prefix
  #
  # The mount prefix is what makes lor routes hard to read in isolation: a
  # route file declares `userRouter:get("/find/:id", …)` and a *different* file
  # (`router.lua`) mounts it with `app:use("/user", userRouter())`, so the real
  # URL is `/user/find/:id`. `userRouter` in the mounting file is bound to
  # `require("app.routes.user")`, so we resolve that require to the route file
  # and prefix every route the file declares. Prefixes compose transitively for
  # nested mounts.
  #
  # Path params use Express `:name` syntax, which already matches noir's URL
  # convention. Verbs come from lor's supported set (get/post/put/delete/patch/
  # head/options/trace and the catch-all `all`).
  class Lor < Analyzer
    # Crystal recompiles an interpolated regex literal on every evaluation, so
    # memoize the route matcher per app/router-variable alternation.
    @route_regexes = Hash(String, Regex).new

    # `app:all(...)` matches every method; surface the common five (the same
    # fallback set the Lapis `app:match` analyzer uses).
    ALL_VERBS = %w[GET POST PUT DELETE PATCH]

    # `local app = lor()` — the application object.
    APP_VAR_RE = /(?:^|[^A-Za-z0-9_.])(?:local\s+)?([A-Za-z_]\w*)\s*=\s*lor\s*\(\s*\)/
    # `local userRouter = lor:Router()` — a router instance.
    ROUTER_VAR_RE = /(?:^|[^A-Za-z0-9_.])(?:local\s+)?([A-Za-z_]\w*)\s*=\s*lor\s*[:.]\s*[Rr]outer\s*\(/
    # `local userRouter = require("app.routes.user")` — module binding.
    REQUIRE_RE = /(?:^|[^A-Za-z0-9_.])(?:local\s+)?([A-Za-z_]\w*)\s*=\s*require\s*\(?\s*(['"])([^'"]+)\2/
    # `app:use("/prefix", userRouter())` — mount a sub-router under a prefix.
    # The second arg must be a bare-variable call (`name(...)`); a `function`
    # literal or table second arg is middleware, not a router mount.
    USE_MOUNT_RE = /\b([A-Za-z_]\w*)\s*[:.]\s*use\s*\(\s*(['"])([^'"]*)\2\s*,\s*([A-Za-z_]\w*)\s*\(/
    # Any `<var>:use(` — used purely to flag a variable as an app/router
    # receiver (lor's App/Router both expose `:use`; redis/db/cache never do).
    USE_RECEIVER_RE = /\b([A-Za-z_]\w*)\s*[:.]\s*use\s*\(/

    private record FileInfo,
      path : String,
      content : String,
      cleaned : String,
      requires : Hash(String, String),
      route_vars : Set(String)

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      files = collect_files
      return @result if files.empty?

      infos = files.map { |path| build_file_info(path) }
      basename_index = build_basename_index(infos)

      file_prefixes = resolve_file_prefixes(infos, basename_index)
      local_mounts = resolve_local_mounts(infos, basename_index)

      infos.each do |info|
        emit_routes(info, include_callee, file_prefixes[info.path]? || "", local_mounts[info.path]? || {} of String => String)
      end

      @result
    end

    private def collect_files : Array(String)
      result = [] of String
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".lua") || path.ends_with?(".moon")
        next if lor_test_path?(path)
        result << path
      end
      result
    end

    # Skip the lor framework's own test suite, which apps vendor under
    # `lib/lor`, `resty/thirdparty/lor`, etc. and which defines dozens of
    # phantom routes against inline test apps. lor uses the Busted `*_spec.lua`
    # convention AND a `*.test.lua` convention (e.g. `test/stack.test.lua`,
    # `test/path_pattern_2.test.lua`), both under `spec*/` or `test*/`
    # directories. Without this, Mio surfaced 20 phantom routes
    # (`/user/123/create`, `/test/foo/bar`, …) from its vendored
    # `resty/thirdparty/lor/test/*.test.lua` and only 1 real route.
    private def lor_test_path?(path : String) : Bool
      base = File.basename(path)
      return true if base.ends_with?("_spec.lua") || base.ends_with?("_spec.moon")
      return true if base.ends_with?(".test.lua") || base.ends_with?(".test.moon")
      expanded_path = File.expand_path(path)

      base_paths.any? do |root|
        next false unless path_under_root?(expanded_path, root)

        expanded_root = File.expand_path(root)
        expanded_root = expanded_root.rstrip('/') unless expanded_root == File::SEPARATOR
        tail = expanded_path[expanded_root.size..]?.try(&.lchop(File::SEPARATOR)) || ""
        tail.split(File::SEPARATOR).any? do |seg|
          seg == "spec" || seg.starts_with?("spec_") || seg == "test" || seg == "tests"
        end
      end
    end

    private def build_file_info(path : String) : FileInfo
      content = read_file_content(path)
      cleaned = Noir::LuaCalleeExtractor.strip_comments(content)
      requires = detect_requires(cleaned)
      route_vars = detect_route_vars(cleaned)
      FileInfo.new(path, content, cleaned, requires, route_vars)
    end

    # `local x = require("a.b.c")` → { "x" => "a.b.c" }.
    private def detect_requires(cleaned : String) : Hash(String, String)
      map = {} of String => String
      cleaned.scan(REQUIRE_RE) do |match|
        name = match[1]
        next if name == "local"
        map[name] = match[3]
      end
      map
    end

    # Variables that can carry routes: the lor app (`lor()`), router instances
    # (`lor:Router()`), and anything used as a `:use(` receiver (a `function(app)`
    # wrapper receives the app as a parameter — it is never assigned via `lor()`
    # but its `app:get(...)` calls are still real routes). Restricting route
    # emission to these vars keeps `redis:get(...)`/`cache:get(...)` calls from
    # leaking as phantom endpoints.
    private def detect_route_vars(cleaned : String) : Set(String)
      vars = Set(String).new
      cleaned.scan(APP_VAR_RE) { |m| vars << m[1] unless m[1] == "local" }
      cleaned.scan(ROUTER_VAR_RE) { |m| vars << m[1] unless m[1] == "local" }
      cleaned.scan(USE_RECEIVER_RE) { |m| vars << m[1] }
      vars
    end

    private def build_basename_index(infos : Array(FileInfo)) : Hash(String, Array(String))
      index = Hash(String, Array(String)).new
      infos.each do |info|
        base = File.basename(info.path)
        (index[base] ||= [] of String) << info.path
      end
      index
    end

    # Resolve a `require("a.b.c")` module string to a scanned file. lor projects
    # set the package root somewhere above the app dir, so we match by path
    # suffix: `a.b.c` → `a/b/c.lua` (or `a/b/c/init.lua`). The most-specific
    # unique suffix match wins; ambiguous names resolve to nil (no prefix).
    private def resolve_module(mod : String, basename_index : Hash(String, Array(String))) : String?
      segments = mod.split('.')
      return if segments.empty?
      last = segments[-1]

      file_fragment = segments.join('/') + ".lua"
      if file = unique_suffix_match(basename_index["#{last}.lua"]?, file_fragment)
        return file
      end

      init_fragment = segments.join('/') + "/init.lua"
      unique_suffix_match(basename_index["init.lua"]?, init_fragment)
    end

    private def unique_suffix_match(candidates : Array(String)?, fragment : String) : String?
      return unless candidates
      matches = candidates.select do |path|
        path == fragment || path.ends_with?("/#{fragment}")
      end
      matches.size == 1 ? matches[0] : nil
    end

    # Cross-file mount edges, composed transitively. A route file `T` mounted
    # by `app:use("/p", reqVar())` in file `F` is served under
    # `prefix(F) + "/p"`. Files that nothing mounts default to the empty prefix
    # (root), which is also what a no-string-prefix mount —
    # `app:use(router()())` — naturally yields, so root routers stay at `/`.
    private def resolve_file_prefixes(infos : Array(FileInfo), basename_index : Hash(String, Array(String))) : Hash(String, String)
      edges = [] of {String, String, String} # {src_file, prefix, dst_file}
      infos.each do |info|
        info.cleaned.scan(USE_MOUNT_RE) do |match|
          prefix = match[3]
          mount_var = match[4]
          mod = info.requires[mount_var]?
          next unless mod
          dst = resolve_module(mod, basename_index)
          next unless dst
          next if dst == info.path # self-mount: handled as a local mount
          edges << {info.path, prefix, dst}
        end
      end

      prefixes = {} of String => String
      # Iterate to a fixpoint so nested mounts compose regardless of file order.
      # Depth is tiny in practice; cap the passes as a runaway guard.
      8.times do
        changed = false
        edges.each do |(src, prefix, dst)|
          next if prefixes.has_key?(dst) # first mount wins (deterministic)
          src_prefix = prefixes[src]? || ""
          prefixes[dst] = join_prefix(src_prefix, prefix)
          changed = true
        end
        break unless changed
      end
      prefixes
    end

    # In-file mounts: `app:use("/p", localRouter())` where `localRouter` is a
    # `lor:Router()` declared in the same file (not a require). Maps the local
    # router variable to its mount prefix so its routes are prefixed.
    private def resolve_local_mounts(infos : Array(FileInfo), basename_index : Hash(String, Array(String))) : Hash(String, Hash(String, String))
      result = {} of String => Hash(String, String)
      infos.each do |info|
        info.cleaned.scan(USE_MOUNT_RE) do |match|
          prefix = match[3]
          mount_var = match[4]
          next if info.requires.has_key?(mount_var) # cross-file: handled above
          map = result[info.path] ||= {} of String => String
          map[mount_var] = prefix unless map.has_key?(mount_var)
        end
      end
      result
    end

    private def emit_routes(info : FileInfo, include_callee : Bool, file_prefix : String, local_mounts : Hash(String, String))
      return if info.route_vars.empty?

      handler_bodies = if include_callee
                         Noir::LuaCalleeExtractor.function_bodies(info.content, info.path)
                       else
                         {} of String => Noir::LuaCalleeExtractor::FunctionBody
                       end

      alt = info.route_vars.to_a.map { |v| Regex.escape(v) }.join("|")
      pattern = @route_regexes[alt] ||= /\b(#{alt})\s*[:.]\s*(get|post|put|delete|patch|head|options|trace|all)\s*\(\s*(['"])([^'"]*)\3/

      info.cleaned.scan(pattern) do |match|
        var = match[1]
        verb = match[2].downcase
        relative = match[4]
        # A confirmed app/router var's verb call is always a route, so the
        # path need not start with `/` — lor mounts relative paths too
        # (`dmRouter:post("getDepartmentMsgByIds", …)` under a `/dm` mount).
        # Empty paths are mount-only artifacts, not endpoints.
        next if relative.empty?

        methods = verb == "all" ? ALL_VERBS : [verb.upcase]

        prefix = local_mounts[var]? ? join_prefix(file_prefix, local_mounts[var]) : file_prefix
        url = join_prefix(prefix, relative)

        route_offset = match.begin(0) || 0
        after_url = (match.end(4) || route_offset) + 1
        callees = include_callee ? route_callees(info.path, info.content, route_offset, after_url, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry

        emit_endpoint(info.path, info.content, route_offset, url, methods, callees)
      end
    end

    private def route_callees(path : String,
                              content : String,
                              route_offset : Int32,
                              after_url : Int32,
                              handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      search_limit, body_limit = route_call_limits(content, route_offset, after_url)
      if body = Noir::LuaCalleeExtractor.extract_function_after(content, after_url, search_limit, body_limit)
        body_text, start_line = body
        return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def route_call_limits(content : String, route_offset : Int32, after_url : Int32) : Tuple(Int32, Int32)
      if open_paren = first_open_paren_before(content, route_offset, after_url)
        if close_paren = Noir::LuaCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
          return {close_paren, close_paren}
        end
      end

      line_end = content.index('\n', after_url) || content.size
      {line_end, content.size}
    end

    private def first_open_paren_before(content : String, start_index : Int32, end_index : Int32) : Int32?
      cursor = start_index
      while cursor < end_index && cursor < content.size
        return cursor if content[cursor] == '('
        cursor += 1
      end
      nil
    end

    private def emit_endpoint(path : String, content : String, offset : Int32,
                              url : String, methods : Array(String),
                              callees : Array(Noir::LuaCalleeExtractor::Entry))
      url = normalize_url(url)
      params = extract_path_params(url)
      line = line_for_offset(content, offset)
      details = Details.new(PathInfo.new(path, line))
      methods.each do |verb|
        endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
        endpoint = Endpoint.new(url, verb, endpoint_params, details)
        Noir::LuaCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        @result << endpoint
      end
    end

    # Concatenate a mount prefix and a route pattern. lor joins the two with a
    # `/`, so an empty pattern collapses to the bare prefix and a slash-prefixed
    # pattern appends cleanly; `normalize_url` collapses any `//` introduced.
    private def join_prefix(prefix : String, relative : String) : String
      combined = if relative.empty?
                   prefix
                 elsif prefix.empty?
                   relative
                 elsif relative.starts_with?("/")
                   "#{prefix}#{relative}"
                 else
                   "#{prefix}/#{relative}"
                 end
      combined = "/#{combined}" unless combined.starts_with?("/")
      combined
    end

    private def normalize_url(url : String) : String
      result = url.gsub(%r{/{2,}}, "/")
      result = result.rchop('/') if result.size > 1 && result.ends_with?('/')
      result = "/" if result.empty?
      result
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/[:*]([A-Za-z_]\w*)/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      content.each_char_with_index do |ch, i|
        break if i >= limit
        count += 1 if ch == '\n'
      end
      count
    end
  end
end
