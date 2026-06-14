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
    # The path must be a rooted URL (`"/..."`). Tokamak handlers commonly build
    # a JSON response with `root.put("name", value)` / `data.get("key")`; those
    # data-object calls share the verb names but never take a `/`-rooted key,
    # so the leading-slash guard keeps them out of the route set.
    ROUTE_RE        = /\.\s*(get|post0|post|put0|put|patch0|patch|delete|head|options)\s*\(\s*"(\/[^"]*)"\s*,\s*([A-Za-z_][\w.]*)/
    ROUTER_MOUNT_RE = /\.\s*router\s*\(\s*([A-Za-z_][\w.]*)\s*\)/
    ROUTE_FN_RE     = /pub\s+fn\s+@"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+(\/[^"]*)"/
    IMPORT_RE       = /(?:pub\s+)?(?:const|var)\s+([A-Za-z_]\w*)\s*=\s*@import\(\s*"([^"]+\.zig)"\s*\)/

    private record GroupFrame, prefix : String, close : Int32

    def analyze
      include_callee = callees_needed?
      zig_files = all_files.select(&.ends_with?(".zig"))

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
        content.includes?(".router(") || content.includes?("pub fn @\"")
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

    # controller file => the URL prefixes it is `.router(...)`-mounted at.
    private def build_router_mounts(files : Array(String), alias_to_file : Hash(String, String)) : Hash(String, Array(String))
      mounts = Hash(String, Array(String)).new
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?(".router(")
        text = Noir::ZigCalleeExtractor.strip_comments(content)
        # `strip_comments` keeps string contents, so `{`/`}` inside a literal
        # would corrupt brace matching. `strip_non_code` blanks strings at the
        # same offsets, so it is the right char array for `find_matching`.
        code_chars = Noir::ZigCalleeExtractor.strip_non_code(content).chars

        events = [] of NamedTuple(kind: Symbol, off: Int32, prefix: String, close: Int32?, target: String)
        text.scan(GROUP_RE) do |m|
          brace = (m.end(0) || 0) - 1
          close = Noir::ZigCalleeExtractor.find_matching(code_chars, brace, '{', '}')
          events << {kind: :group, off: m.begin(0) || 0, prefix: m[1], close: close, target: ""}
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
          target_file = alias_to_file[ev[:target].split('.').last]?
          next if target_file.nil?
          prefix = stack.reduce("") { |acc, frame| Noir::URLPath.join(acc, frame.prefix) }
          list = mounts[target_file] ||= [] of String
          list << prefix unless list.includes?(prefix)
        end
      end
      mounts
    end

    private def process_file(path : String, content : String, mounts : Hash(String, Array(String)), include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      # Strings preserved in `text` for reading paths/handlers; brace matching
      # runs on the string-blanked (but offset-identical) char array so a `{`/`}`
      # inside a literal can't throw off group-scope tracking.
      code_chars = Noir::ZigCalleeExtractor.strip_non_code(content).chars
      bodies = include_callee ? Noir::ZigCalleeExtractor.function_bodies(content, path) : {} of String => Noir::ZigCalleeExtractor::FunctionBody

      emit_route_array(path, text, code_chars, bodies, include_callee)
      emit_controller_routes(path, content, text, mounts, include_callee)
    end

    # Inline `tk.Route` array routes (.get/.post/.group/…).
    private def emit_route_array(path, text, code_chars, bodies, include_callee)
      events = collect_events(text, code_chars)
      stack = [] of GroupFrame

      events.each do |ev|
        stack.reject! { |frame| frame.close < ev[:off] }

        if ev[:kind] == :group
          close = ev[:close]
          stack << GroupFrame.new(ev[:prefix], close) if close
          next
        end

        prefix = stack.reduce("") { |acc, frame| Noir::URLPath.join(acc, frame.prefix) }
        url = Noir::URLPath.join(prefix, ev[:path])
        name = ev[:handler].includes?('.') ? ev[:handler].split('.').last : ev[:handler]
        callees = include_callee ? body_callees(bodies, name, path) : [] of Noir::ZigCalleeExtractor::Entry
        emit(path, text, ev[:off], url, ev[:method], callees)
      end
    end

    # `pub fn @"METHOD /path"` controller handlers, prefixed by every
    # `.router(...)` mount point that targets this file (or bare when the file
    # isn't mounted, or its mount chain crosses a route-value reference we
    # don't expand).
    private def emit_controller_routes(path, content, text, mounts, include_callee)
      return unless content.includes?("pub fn @\"")
      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      stripped_chars = stripped.chars
      prefixes = mounts[File.expand_path(path)]?
      prefixes = [""] if prefixes.nil? || prefixes.empty?

      text.scan(ROUTE_FN_RE) do |m|
        method = m[1]
        rel = m[2]
        offset = m.begin(0) || 0
        callees = include_callee ? route_fn_callees(stripped_chars, m.end(0) || 0, path) : [] of Noir::ZigCalleeExtractor::Entry
        prefixes.each do |pre|
          emit(path, text, offset, Noir::URLPath.join(pre, rel), method, callees)
        end
      end
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
  end
end
