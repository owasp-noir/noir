require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"
require "../../../utils/url_path"

module Analyzer::Zig
  # Tokamak declares routes two ways:
  #
  #   1. Inline `tk.Route` arrays:
  #        const routes: []const tk.Route = &.{
  #          .get("/", hello),
  #          .group("/api", &.{ .get("/health", health) }),
  #        };
  #      `.group(prefix, &.{ … })` composes its prefix onto every nested route;
  #      `.post0`/`.put0`/`.patch0` are body-less verb variants.
  #
  #   2. Controller modules mounted with `.router(T)`. The controller declares
  #      one handler per route, naming the function with the method + path:
  #        pub fn @"GET /chat/:id"(db: *Session, id: u32) !Chat { … }
  #      `.router(chat)` (where `chat = @import("api/chat.zig")`) mounts every
  #      such function, composing any enclosing `.group(...)` prefix. The
  #      mount and the controller usually live in different files, so the
  #      mount prefixes are resolved project-wide and keyed by controller file.
  #
  # A controller's routes can also be declared as `const` bindings rather than
  # functions — the handler lives in another file and the route is just a name:
  #
  #   pub const Protected = struct {
  #       pub const @"GET /projects" = getAllProjects;
  #       pub const @"PUT /projects/:id" = updateProject;
  #   };
  #
  # Such structs are mounted by *qualified* name (`.router(api.Protected)`,
  # where `api = @import("api.zig")` and `Protected` is a struct inside it), so
  # the route set of one file is partitioned across several mounts. Each route
  # therefore carries the prefix of every mount that targets its enclosing
  # struct (or any whole-file mount).
  #
  # Not yet resolved: a `.group(prefix, RouteConst)` whose body is a reference
  # to a `tk.Route` const (rather than an inline `&.{ … }` array) — those
  # controllers' routes are emitted without the referenced-group prefix.
  class Tokamak < Analyzer
    VERB_METHOD = {
      "get" => "GET", "post" => "POST", "post0" => "POST", "put" => "PUT",
      "put0" => "PUT", "patch" => "PATCH", "patch0" => "PATCH",
      "delete" => "DELETE", "head" => "HEAD", "options" => "OPTIONS",
    }

    GROUP_RE = /\.\s*group\s*\(\s*"([^"]*)"\s*,\s*&?\s*\.\s*\{/
    # Value-form group whose body is a single route value rather than an
    # `&.{ … }` array (`tk.group("/api", tk.router(api))`). The negative
    # lookahead — which must absorb its own leading whitespace, so a
    # backtracking `\s*` can't slip past it — keeps the array form to GROUP_RE.
    GROUP_VALUE_RE = /\.\s*group\s*\(\s*"([^"]*)"\s*,(?!\s*&?\s*\.\s*\{)/
    # The path must be a rooted URL (`"/..."`). Tokamak handlers commonly build
    # a JSON response with `root.put("name", value)` / `data.get("key")`; those
    # data-object calls share the verb names but never take a `/`-rooted key,
    # so the leading-slash guard keeps them out of the route set.
    ROUTE_RE        = /\.\s*(get|post0|post|put0|put|patch0|patch|delete|head|options)\s*\(\s*"(\/[^"]*)"\s*,\s*([A-Za-z_][\w.]*)/
    ROUTER_MOUNT_RE = /\.\s*router\s*\(\s*([A-Za-z_][\w.]*)\s*\)/
    ROUTE_FN_RE     = /pub\s+fn\s+@"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(\/[^"]*)"/
    ROUTE_CONST_RE  = /pub\s+const\s+@"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(\/[^"]*)"/
    STRUCT_DECL_RE  = /(?:^|[^A-Za-z0-9_.])(?:pub\s+)?const\s+([A-Za-z_]\w*)\s*=\s*struct\s*\{/
    IMPORT_RE       = /(?:pub\s+)?(?:const|var)\s+([A-Za-z_]\w*)\s*=\s*@import\(\s*"([^"]+\.zig)"\s*\)/

    private record GroupFrame, prefix : String, close : Int32
    # A `.router(...)` mount targeting a controller file. `scope` is the struct
    # name within that file the mount selects (`.router(api.Protected)`), or nil
    # for a whole-file mount (`.router(chat)`).
    private record RouterMount, scope : String?, prefix : String
    private record StructRegion, name : String, start : Int32, stop : Int32

    def analyze
      include_callee = callees_needed?
      zig_files = all_files.select do |f|
        f.ends_with?(".zig") && !Noir::ZigCalleeExtractor.vendored_framework_path?(f)
      end

      alias_to_file = build_alias_map(zig_files)
      mounts = build_router_mounts(zig_files, alias_to_file)

      zig_files.each do |path|
        content = read_file_content(path)
        next unless route_file?(content)
        process_file(path, content, mounts, include_callee)
      end

      @result
    end

    private def route_file?(content : String) : Bool
      content.includes?("tk.Route") || content.includes?(".group(") ||
        content.includes?(".router(") || content.includes?("pub fn @\"") ||
        content.includes?("pub const @\"")
    end

    # alias identifier => absolute file it `@import`s.
    private def build_alias_map(files : Array(String)) : Hash(String, String)
      map = {} of String => String
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("@import")
        dir = File.dirname(path)
        Noir::ZigCalleeExtractor.strip_comments(content).scan(IMPORT_RE) do |m|
          map[m[1]] = File.expand_path(File.join(dir, m[2]))
        end
      end
      map
    end

    # controller file => the `.router(...)` mounts that target it (prefix +
    # optional struct scope).
    private def build_router_mounts(files : Array(String), alias_to_file : Hash(String, String)) : Hash(String, Array(RouterMount))
      mounts = Hash(String, Array(RouterMount)).new
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?(".router(")
        text = Noir::ZigCalleeExtractor.strip_comments(content)
        # `strip_comments` keeps string contents, so `{`/`}` inside a literal
        # would corrupt brace matching. `strip_non_code` blanks strings at the
        # same offsets, so it is the right char array for `find_matching`.
        stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
        code_chars = stripped.chars
        local_structs = struct_regions(stripped).map(&.name)

        events = [] of NamedTuple(kind: Symbol, off: Int32, prefix: String, close: Int32?, target: String)
        # Array-form group: `.group("/p", &.{ … })` — scoped by its body braces.
        text.scan(GROUP_RE) do |m|
          brace = (m.end(0) || 0) - 1
          close = Noir::ZigCalleeExtractor.find_matching(code_chars, brace, '{', '}')
          events << {kind: :group, off: m.begin(0) || 0, prefix: m[1], close: close, target: ""}
        end
        # Value-form group: `.group("/p", tk.router(x))` — the body is a single
        # route value, not a `&.{ … }` array, so the scope is the group call's
        # own parentheses.
        text.scan(GROUP_VALUE_RE) do |m|
          start = m.begin(0) || 0
          paren = index_of(code_chars, start, '(')
          next if paren.nil?
          close = Noir::ZigCalleeExtractor.find_matching(code_chars, paren, '(', ')')
          events << {kind: :group, off: start, prefix: m[1], close: close, target: ""}
        end
        text.scan(ROUTER_MOUNT_RE) do |m|
          events << {kind: :router, off: m.begin(0) || 0, prefix: "", close: nil, target: m[1]}
        end
        events.sort_by! { |ev| ev[:off] }

        stack = [] of GroupFrame
        events.each do |ev|
          stack.reject! { |frame| frame.close < ev[:off] }
          if ev[:kind] == :group
            close = ev[:close]
            stack << GroupFrame.new(ev[:prefix], close) if close
            next
          end
          resolved = resolve_router_target(ev[:target], alias_to_file, File.expand_path(path), local_structs)
          next if resolved.nil?
          target_file, scope = resolved
          prefix = stack.reduce("") { |acc, frame| Noir::URLPath.join(acc, frame.prefix) }
          list = mounts[target_file] ||= [] of RouterMount
          mount = RouterMount.new(scope, prefix)
          list << mount unless list.includes?(mount)
        end
      end
      mounts
    end

    # A `.router(target)` argument resolves to a controller file (+ optional
    # struct scope inside it):
    #   * `.router(chat)` / `.router(api.push)` — the simple/last identifier is
    #     itself a `@import` alias → whole-file mount (scope nil).
    #   * `.router(api.Protected)` — `api` is the file alias, `Protected` a
    #     struct declared inside it → file-scoped to that struct.
    #   * `.router(api)` — `api` is a `const api = struct { … }` declared in the
    #     current file → same-file mount scoped to that struct.
    private def resolve_router_target(target : String, alias_to_file : Hash(String, String), current_file : String, local_structs : Array(String)) : Tuple(String, String?)?
      segments = target.split('.')
      if file = alias_to_file[segments.last]?
        return {file, nil}
      end
      if segments.size > 1
        if file = alias_to_file[segments.first]?
          return {file, segments[1]}
        end
      end
      if segments.size == 1 && local_structs.includes?(segments.first)
        return {current_file, segments.first}
      end
      nil
    end

    private def process_file(path : String, content : String, mounts : Hash(String, Array(RouterMount)), include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      # Strings preserved in `text` for reading paths/handlers; brace matching
      # runs on the string-blanked (but offset-identical) char array so a `{`/`}`
      # inside a literal can't throw off group-scope tracking.
      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      code_chars = stripped.chars
      bodies = include_callee ? Noir::ZigCalleeExtractor.function_bodies(content, path) : {} of String => Noir::ZigCalleeExtractor::FunctionBody
      # Routes declared inside `test { … }` blocks are unit-test fixtures (e.g.
      # tokamak's own client tests register `.get("/ping", …)`), not endpoints.
      test_blocks = Noir::ZigCalleeExtractor.test_block_ranges(stripped)

      emit_route_array(path, text, code_chars, bodies, test_blocks, include_callee)
      emit_controller_routes(path, content, text, mounts, test_blocks, include_callee)
    end

    # Inline `tk.Route` array routes (.get/.post/.group/…).
    private def emit_route_array(path, text, code_chars, bodies, test_blocks, include_callee)
      events = collect_events(text, code_chars)
      stack = [] of GroupFrame

      events.each do |ev|
        stack.reject! { |frame| frame.close < ev[:off] }

        if ev[:kind] == :group
          close = ev[:close]
          stack << GroupFrame.new(ev[:prefix], close) if close
          next
        end

        next if Noir::ZigCalleeExtractor.in_test_block?(ev[:off], test_blocks)
        prefix = stack.reduce("") { |acc, frame| Noir::URLPath.join(acc, frame.prefix) }
        url = join_route(prefix, ev[:path])
        name = ev[:handler].includes?('.') ? ev[:handler].split('.').last : ev[:handler]
        callees = include_callee ? body_callees(bodies, name, path) : [] of Noir::ZigCalleeExtractor::Entry
        emit(path, text, ev[:off], url, ev[:method], callees)
      end
    end

    # `pub fn @"METHOD /path"` / `pub const @"METHOD /path"` controller routes,
    # prefixed by every `.router(...)` mount that targets this file (whole-file
    # mounts apply to top-level routes; struct-scoped mounts apply to routes
    # inside the matching struct). Falls back to bare when the file isn't
    # mounted, or its mount chain crosses a route-value reference we don't
    # expand. `const` routes name a handler defined elsewhere, so they carry no
    # inline body and thus no callees.
    private def emit_controller_routes(path, content, text, mounts, test_blocks, include_callee)
      has_fn = content.includes?("pub fn @\"")
      has_const = content.includes?("pub const @\"")
      return unless has_fn || has_const

      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      stripped_chars = stripped.chars
      file_mounts = mounts[File.expand_path(path)]?
      regions = struct_regions(stripped)

      if has_fn
        text.scan(ROUTE_FN_RE) do |m|
          method = m[1]
          rel = m[2]
          offset = m.begin(0) || 0
          next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
          callees = include_callee ? route_fn_callees(stripped_chars, m.end(0) || 0, path) : [] of Noir::ZigCalleeExtractor::Entry
          prefixes_for(file_mounts, enclosing_struct(regions, offset)).each do |pre|
            emit(path, text, offset, join_route(pre, rel), method, callees)
          end
        end
      end

      if has_const
        text.scan(ROUTE_CONST_RE) do |m|
          method = m[1]
          rel = m[2]
          offset = m.begin(0) || 0
          next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
          prefixes_for(file_mounts, enclosing_struct(regions, offset)).each do |pre|
            emit(path, text, offset, join_route(pre, rel), method, [] of Noir::ZigCalleeExtractor::Entry)
          end
        end
      end
    end

    # Struct declaration regions (`const X = struct { … }`), brace-matched on
    # the string-blanked char array, so a `@"…"` route name can be attributed
    # to its enclosing struct.
    private def struct_regions(stripped : String) : Array(StructRegion)
      chars = stripped.chars
      regions = [] of StructRegion
      stripped.scan(STRUCT_DECL_RE) do |m|
        name = m[1]
        brace = (m.end(0) || 0) - 1
        close = Noir::ZigCalleeExtractor.find_matching(chars, brace, '{', '}')
        next if close.nil?
        regions << StructRegion.new(name, brace, close)
      end
      regions
    end

    # The name of the innermost struct region containing `offset`, or nil for a
    # top-level (file-scope) declaration.
    private def enclosing_struct(regions : Array(StructRegion), offset : Int32) : String?
      best : StructRegion? = nil
      regions.each do |r|
        next unless offset > r.start && offset < r.stop
        best = r if best.nil? || (r.stop - r.start) < (best.stop - best.start)
      end
      best.try(&.name)
    end

    # Prefixes a route at `scope` (its enclosing struct name, or nil) inherits:
    # every whole-file mount plus every mount selecting this struct. Bare when
    # the file has no resolvable mounts.
    private def prefixes_for(file_mounts : Array(RouterMount)?, scope : String?) : Array(String)
      return [""] if file_mounts.nil? || file_mounts.empty?
      whole = file_mounts.select(&.scope.nil?).map(&.prefix)
      scoped = scope ? file_mounts.select { |m| m.scope == scope }.map(&.prefix) : [] of String
      result = (whole + scoped).uniq
      result.empty? ? [""] : result
    end

    # Group-open and route events, ordered by source offset, so a single pass
    # with a brace-keyed stack reconstructs the prefix in scope for each route.
    private def collect_events(text : String, code_chars : Array(Char))
      events = [] of NamedTuple(kind: Symbol, off: Int32, prefix: String, close: Int32?, path: String, method: String, handler: String)

      text.scan(GROUP_RE) do |m|
        brace_open = (m.end(0) || 0) - 1
        close = Noir::ZigCalleeExtractor.find_matching(code_chars, brace_open, '{', '}')
        events << {kind: :group, off: m.begin(0) || 0, prefix: m[1], close: close, path: "", method: "", handler: ""}
      end

      text.scan(ROUTE_RE) do |m|
        verb = m[1]
        method = VERB_METHOD[verb]?
        next if method.nil?
        events << {kind: :route, off: m.begin(0) || 0, prefix: "", close: nil, path: m[2], method: method, handler: m[3]}
      end

      events.sort_by { |ev| ev[:off] }
    end

    private def body_callees(bodies, name, path) : Array(Noir::ZigCalleeExtractor::Entry)
      if body = bodies[name]?
        return Noir::ZigCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
      end
      [] of Noir::ZigCalleeExtractor::Entry
    end

    # The 1-hop callees inside a `@"METHOD /path"` function body. `function_table`
    # keys on plain `fn name(`, so the `@"…"`-named handlers are resolved here
    # directly by brace-matching from the function header.
    private def route_fn_callees(chars : Array(Char), after_name : Int32, path : String) : Array(Noir::ZigCalleeExtractor::Entry)
      paren = index_of(chars, after_name, '(')
      return [] of Noir::ZigCalleeExtractor::Entry if paren.nil?
      close_paren = Noir::ZigCalleeExtractor.find_matching(chars, paren, '(', ')')
      return [] of Noir::ZigCalleeExtractor::Entry if close_paren.nil?
      brace = index_of(chars, close_paren + 1, '{')
      return [] of Noir::ZigCalleeExtractor::Entry if brace.nil?
      close_brace = Noir::ZigCalleeExtractor.find_matching(chars, brace, '{', '}')
      return [] of Noir::ZigCalleeExtractor::Entry if close_brace.nil?

      body = String.build do |io|
        i = brace + 1
        while i < close_brace && i < chars.size
          io << chars[i]
          i += 1
        end
      end
      Noir::ZigCalleeExtractor.callees_for_body(body, path, Noir::ZigCalleeExtractor.line_at(chars, brace))
    end

    private def index_of(chars : Array(Char), from : Int32, char : Char) : Int32?
      i = from
      while i < chars.size
        return i if chars[i] == char
        i += 1
      end
      nil
    end

    private def emit(path, text, offset, url, method, callees : Array(Noir::ZigCalleeExtractor::Entry))
      params = extract_path_params(url)
      line = Noir::ZigCalleeExtractor.line_at(text.chars, offset)
      details = Details.new(PathInfo.new(path, line))
      endpoint = Endpoint.new(url, method, params, details)
      Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
      @result << endpoint
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_]\w*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    # Join a mount/group prefix with a route path. A bare-root route ("/")
    # mounted under a non-empty prefix collapses to the prefix itself rather
    # than picking up a trailing slash (`/api` + `/` => `/api`, not `/api/`).
    private def join_route(prefix : String, route : String) : String
      return prefix if route == "/" && !prefix.empty?
      Noir::URLPath.join(prefix, route)
    end
  end
end
