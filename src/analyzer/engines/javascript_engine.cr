require "../../utils/char_offsets"
require "../../models/analyzer"
require "../../miniparsers/js_callee_extractor"

module Analyzer::Javascript
  abstract class JavascriptEngine < Analyzer
    # Default extension set for JavaScript/TypeScript source files.
    # Analyzers with a different filter (e.g. Nitro adds `.mts`, NestJS JS
    # only uses `.js`/`.jsx`) pass their own list to `parallel_file_scan`.
    #
    # This list mirrors what the JS detectors declare in `extensions:`
    # (`.js .mjs .cjs .jsx .ts .mts .cts .tsx`). It has to: detection and analysis
    # read the same tree, so any extension a detector accepts but this
    # list omits produces a project that detects fine and then yields
    # zero endpoints, with nothing logged and nothing for `--strict` to
    # report. `.mjs`/`.cjs` were exactly that hole — an ESM Express app
    # (`app.mjs`) detected as `js_express` and returned no routes.
    # Analyzers that pass their own list (koa, hapi, sails, adonisjs,
    # elysia, feathers, ...) already spelled `.mjs`/`.cjs` out by hand;
    # the six that relied on this default (express, fastify, hono,
    # restify, apollo, graphql_yoga, plus socketio) silently did not.
    DEFAULT_EXTENSIONS      = [".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx"]
    JS_PROJECT_ROOT_MARKERS = [
      "package.json",
      "next.config.js", "next.config.ts", "next.config.mjs", "next.config.cjs",
      "svelte.config.js", "svelte.config.ts", "svelte.config.mjs", "svelte.config.cjs",
    ]

    # Walk matching source files concurrently. Candidates come from the
    # CodeLocator extension index so monorepo `file_map` entries in other
    # languages never enter the channel. Paths are detector-registered
    # regular files — skip the redundant `File.exists?` / `File.directory?`
    # syscalls (missing files surface as read errors and are logged).
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    protected def parallel_file_scan(extensions : Array(String) = DEFAULT_EXTENSIONS, &block : String -> Nil) : Nil
      scan_files(get_files_by_extensions(extensions), &block)
    end

    # Crystal recompiles an interpolated regex literal (/...#{x}.../) on
    # every evaluation — a full PCRE2 JIT compile. Patterns keyed by a
    # discovered name ("req", "query", "body", router vars, ...) are
    # low-cardinality across a scan, so memoize them per analyzer
    # instance. Fibers are cooperative (no preview_mt), so the plain
    # Hash is safe under parallel_file_scan.
    @dynamic_regex_cache = Hash(String, Regex).new

    protected def cached_regex(key : String, & : -> Regex) : Regex
      @dynamic_regex_cache.fetch(key) do
        @dynamic_regex_cache[key] = yield
      end
    end

    protected def attach_js_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry))
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    protected def javascript_source_language(path : String) : Symbol
      path.ends_with?(".ts") || path.ends_with?(".mts") || path.ends_with?(".cts") || path.ends_with?(".tsx") ? :typescript : :javascript
    end

    # Endpoint for a file-routed framework (Astro, Fresh, Remix, SvelteKit):
    # every `{name}` placeholder in the URL becomes a path param.
    protected def file_route_endpoint(url : String, verb : String, path : String, line : Int32 = 1) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      endpoint
    end

    # `MatchData#begin` is a CHAR index; the inherited helper is the one
    # that converts it to a byte offset before counting newlines. This used
    # to slice `content.to_slice[0, start]` with the char index directly,
    # which undercounts on any source with non-ASCII before the match.
    protected def line_for_match(content : String, match : Regex::MatchData) : Int32
      line_number_for_index(content, match.begin(0) || 0)
    end

    # Verb-named exports of a file-routed API module (Astro, SvelteKit).
    FILE_ROUTE_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]

    # Lowest-cost defaults for endpoints whose handler doesn't
    # advertise its verbs explicitly. Mirrors the Next.js fallback.
    FALLBACK_API_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Compiled once per verb — interpolated regex literals would otherwise
    # be rebuilt (full PCRE2 compile) for every method on every file.
    EXPORT_FUNCTION_RES = FILE_ROUTE_METHODS.map { |m| {m, /export\s+(?:async\s+)?function\s+#{m}\b/} }.to_h
    EXPORT_CONST_RES    = FILE_ROUTE_METHODS.map { |m| {m, /export\s+(?:const|let|var)\s+#{m}\b\s*(?::[^=]+)?=/} }.to_h
    EXPORT_BRACE_RES    = FILE_ROUTE_METHODS.map { |m| {m, /export\s+\{\s*[^}]*\b#{m}\b[^}]*\}/} }.to_h

    # Look for explicit verb exports first
    # (`export const GET = ...` / `export async function POST() {}`),
    # then fall back to the cross-method catch-all set.
    protected def detect_api_methods(content : String) : Array(String)
      explicit = explicit_api_methods(content)
      explicit.empty? ? FALLBACK_API_METHODS : explicit
    end

    # `export async function GET(...)`, `export function GET(...)`,
    # `export const GET = ...`, `export const GET: APIRoute = ...`
    # (the trailing TypeScript type annotation is optional), and
    # the `export { GET }` re-export form.
    protected def explicit_api_methods(content : String) : Array(String)
      FILE_ROUTE_METHODS.select do |m|
        content.matches?(EXPORT_FUNCTION_RES[m]) ||
          content.matches?(EXPORT_CONST_RES[m]) ||
          content.matches?(EXPORT_BRACE_RES[m])
      end
    end

    # A route module's page component (SolidStart, Qwik City). Line-anchored
    # without consuming earlier lines, so `line_for_match` lands on it.
    DEFAULT_EXPORT_RE = /^[ \t]*export\s+default\b/m

    # Route-directory segments → URL for the `src/routes/` conventions
    # (SvelteKit, SolidStart, Qwik City): `(group)` segments are hidden and
    # every param group normalizes to `{name}`, in place, so static text
    # around it survives (`foo-[id]`, `@[user]`):
    #   [id]  [id=int]  [...rest]  [[opt]]  [[opt=int]]  [[...rest]]
    FILE_ROUTE_PARAM_RE = /\[+(?:\.{3})?(\w+)(?:=\w+)?\]+/

    # Path below `src/routes/`, or nil outside it. Scan-base-relative, never
    # absolute: `String#index` takes the FIRST occurrence, so a same-named
    # directory above the scan base won outright and the derived URL changed
    # with the checkout path.
    protected def src_routes_relative(path : String) : String?
      scoped = base_relative_path(path)
      idx = scoped.index("/src/routes/") || return
      scoped[(idx + "/src/routes/".size)..]
    end

    protected def file_route_url(segments : Array(String)) : String
      mapped = segments.compact_map do |seg|
        next if seg.empty? || (seg.starts_with?('(') && seg.ends_with?(')'))
        seg.gsub(FILE_ROUTE_PARAM_RE) { "{#{$1}}" }
      end
      "/" + mapped.join('/')
    end

    protected def api_method_line(content : String, verb : String) : Int32?
      if match = content.match(EXPORT_FUNCTION_RES[verb])
        return line_for_match(content, match)
      end

      if match = content.match(EXPORT_CONST_RES[verb])
        return line_for_match(content, match)
      end

      if content.includes?("export {") && content.includes?(verb)
        Noir::JSCalleeExtractor.exported_function_line(content, verb)
      end
    end

    protected def collect_static_paths(source_path : String, content : String, static_dirs : Array(Hash(String, String)), framework : Symbol? = nil) : Nil
      Noir::JSRouteExtractor.extract_static_paths(content, framework).each do |static_path|
        normalized = static_path.dup
        normalized["file_path"] = resolve_static_file_path(source_path, normalized["file_path"])
        static_dirs << normalized unless static_dirs.any? { |s| s["static_path"] == normalized["static_path"] && s["file_path"] == normalized["file_path"] }
      end
    end

    protected def process_js_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint)) : Nil
      # Reuse CodeLocator's once-built expanded file map instead of
      # re-running File.expand_path + File.directory? across every
      # static dir (and across every concurrent JS analyzer).
      files = all_files_expanded
      # GET urls already emitted (routes and earlier static files). A Set
      # instead of `result.any?` per file, which went quadratic on large
      # asset trees.
      seen_get = result.compact_map { |e| e.url if e.method == "GET" }.to_set

      static_dirs.each do |dir|
        root = Noir::PathScope.normalize_root(dir["file_path"])
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        files.each do |file_path, expanded_file_path|
          next unless Noir::PathScope.under_normalized_root?(expanded_file_path, root)

          relative_path = expanded_file_path[root.size..]?.try(&.lchop('/')) || ""
          next if relative_path.empty?

          url = if static_path == "/" || static_path.empty?
                  "/#{relative_path}"
                else
                  "#{static_path}/#{relative_path}"
                end
          url = url.squeeze('/')

          next unless seen_get.add?(url)
          result << Endpoint.new(url, "GET", Details.new(PathInfo.new(file_path)))
        end
      end
    end

    # True when this file has already contributed `method url` to `result`.
    #
    # The auxiliary passes each analyzer runs after the shared extractor
    # (Fastify's `route({…})` config objects, Hono's `app.on(…)`, the
    # regex fallbacks) re-read routes the extractor may have emitted for the
    # same file, so they need a "did I already record this?" guard. Written
    # as a bare `result.any? { |e| e.url == url && e.method == method }` that
    # guard reaches across the *whole run*: `result` accumulates every file's
    # endpoints, so a route was dropped because a different file happened to
    # declare the same address first. Two services in one repo both serving
    # `GET /items/:id` reported a single endpoint carrying one of the two
    # source locations, and which one survived depended on the order the
    # worker pool handed the files over — the same scan named a different
    # file between runs.
    #
    # Matching the file as well keeps the intra-file de-duplication the
    # guard exists for and lets a genuine second declaration through, where
    # the optimizer merges the two into one endpoint with both code paths.
    protected def route_recorded_for_file?(result : Array(Endpoint), path : String, url : String, method : String) : Bool
      result.any? do |endpoint|
        endpoint.url == url && endpoint.method == method &&
          endpoint.details.code_paths.any? { |code_path| code_path.path == path }
      end
    end

    protected def discover_js_project_roots(package_markers : Array(String), config_basenames : Array(String)) : Array(String)
      roots = [] of String

      all_files.each do |file|
        base = File.basename(file)
        if config_basenames.includes?(base)
          add_project_root(roots, File.dirname(file))
        elsif base == "package.json"
          begin
            content = read_file_content(file)
          rescue IO::Error
            next
          end
          add_project_root(roots, File.dirname(file)) if package_markers.any? { |marker| content.includes?(marker) }
        end
      end

      roots
    end

    # Expanded directory of every package.json → whether it names one of
    # `package_markers`. Pair with `owned_by_js_package?` where frameworks
    # share one layout (`src/routes/`): unlike `path_under_project_roots?`,
    # a hoisted root package.json does not claim the apps nested below it.
    protected def js_package_owners(package_markers : Array(String)) : Hash(String, Bool)
      owners = {} of String => Bool
      all_files.each do |file|
        next unless File.basename(file) == "package.json"
        content = begin
          read_file_content(file)
        rescue IO::Error
          next
        end
        owners[File.dirname(Noir::PathScope.expand(file))] = package_markers.any? { |marker| content.includes?(marker) }
      end
      owners
    end

    # Whether the closest package.json above `path` names the framework.
    protected def owned_by_js_package?(path : String, owners : Hash(String, Bool)) : Bool
      js_package_dir(path, owners).try { |dir| owners[dir] } || false
    end

    # Directory of the closest package.json above `path` (a key of `owners`).
    protected def js_package_dir(path : String, owners : Hash(String, Bool)) : String?
      dir = File.dirname(Noir::PathScope.expand(path))
      loop do
        return dir if owners.has_key?(dir)
        parent = File.dirname(dir)
        return if parent == dir
        dir = parent
      end
    end

    protected def path_under_project_roots?(path : String, roots : Array(String)) : Bool
      return true if roots.empty?

      expanded = Noir::PathScope.expand(path)
      roots.any? do |root|
        Noir::PathScope.under_normalized_root?(expanded, root)
      end
    end

    protected def handler_callees(handler_source : String, handler_start : Int32, content : String, path : String) : Array(Noir::JSCalleeExtractor::Entry)
      if arrow_idx = handler_source.index("=>")
        body_start = skip_whitespace(content, handler_start + arrow_idx + 2)
        return [] of Noir::JSCalleeExtractor::Entry if body_start >= content.size

        if content[body_start]? == '{'
          return block_handler_callees(content, path, body_start)
        end

        body = content[body_start...(handler_start + handler_source.size)].strip
        return [] of Noir::JSCalleeExtractor::Entry if body.empty?

        return Noir::JSCalleeExtractor.callees_for_function_body(body, path, line_number_for_index(content, body_start), language: javascript_source_language(path))
      end

      function_idx = handler_source.index(/\bfunction\b/)
      return [] of Noir::JSCalleeExtractor::Entry unless function_idx

      open_brace = content.index("{", handler_start + function_idx)
      return [] of Noir::JSCalleeExtractor::Entry unless open_brace

      block_handler_callees(content, path, open_brace)
    end

    protected def block_handler_callees(content : String, path : String, open_brace : Int32) : Array(Noir::JSCalleeExtractor::Entry)
      close_brace = Noir::JSRouteExtractor.find_matching_brace(content, open_brace)
      return [] of Noir::JSCalleeExtractor::Entry unless close_brace

      body = content[(open_brace + 1)...close_brace]
      Noir::JSCalleeExtractor.callees_for_function_body(body, path, line_number_for_index(content, open_brace), language: javascript_source_language(path))
    end

    protected def split_top_level_args(content : String, start_pos : Int32, end_pos : Int32) : Array(Tuple(String, Int32))
      Noir::TopLevelSplit.split_spans(content, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, start_pos, end_pos)
    end

    protected def skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    # Same walk without `content[i]`, which is O(i) on a non-ASCII string.
    protected def skip_whitespace(offsets : Noir::CharOffsets, pos : Int32) : Int32
      i = pos
      while (char = offsets.char_at(i)) && char.whitespace?
        i += 1
      end
      i
    end

    # Resolve every router variable's mount prefix(es) from the edge list.
    # A variable that is never mounted into another (a root aggregator like
    # the exported `router`) carries the empty prefix; children inherit the
    # parent's prefix joined with the edge's own prefix. Propagation is
    # cycle-safe (see `JSRouteExtractor.propagate_mount_prefixes`).
    protected def resolve_mount_edge_prefixes(edges : Array(Tuple(String, String, String))) : Hash(String, Array(String))
      children = edges.map { |_, _, child| child }.to_set
      prefixes = Hash(String, Array(String)).new

      # Seed roots (never a mount target) with the empty prefix. Only
      # resolved parents propagate: defaulting an unresolved parent to ""
      # would leak a wrong prefix (`/sub` instead of `/api/sub`).
      edges.each do |parent, _, _|
        prefixes[parent] = [""] unless children.includes?(parent)
      end

      if Noir::JSRouteExtractor.propagate_mount_prefixes(edges, prefixes)
        logger.debug "Mount prefixes capped at #{Noir::JSRouteExtractor::MAX_MOUNT_PREFIXES} per router"
      end
      prefixes
    end

    # Byte-indexed mask of every position inside a '...' / "..." / `...`
    # literal, so regex hits inside strings can be skipped.
    protected def string_literal_mask(content : String) : Array(Bool)
      mask = Array(Bool).new(content.bytesize, false)
      i = 0

      while i < content.bytesize
        byte = content.byte_at(i)
        if byte == '\''.ord || byte == '"'.ord || byte == '`'.ord
          quote = byte
          mask[i] = true
          i += 1

          while i < content.bytesize
            current = content.byte_at(i)
            mask[i] = true

            if current == '\\'.ord && i + 1 < content.bytesize
              i += 1
              mask[i] = true
            elsif current == quote
              i += 1
              break
            end

            i += 1
          end
        else
          i += 1
        end
      end

      mask
    end

    protected def literal_position?(literal_mask : Array(Bool), pos : Int32?) : Bool
      return false unless pos
      pos < literal_mask.size && literal_mask[pos]
    end

    # Signature of the class method that follows a run of decorators.
    # `dotted_decorator_names` lets a decorator name contain `.`
    # (LoopBack's `@requestBody.file()`); NestJS names stop at `.`.
    # `\G` anchors at the match offset, so the signature is matched in place
    # rather than on a copy of the rest of the class per route decorator.
    METHOD_SIGNATURE_AT = /\G\s*(?:(?:public|private|protected|static|async|readonly|override)\s+)*([A-Za-z_$][\w$]*)\s*\(/

    #
    # `chars` is `content.chars` when the caller already holds it. A
    # non-ASCII `content` is otherwise materialized once here, and every
    # offset is then found and sliced on it: char-indexed `String` calls
    # re-decode UTF-8 from the start of the class on each use, which made a
    # many-route controller with one non-ASCII char quadratic.
    protected def method_signature_after_decorators(content : String, start_pos : Int32, dotted_decorator_names : Bool = false,
                                                    chars : Array(Char)? = nil)
      src = chars || (content.bytesize == content.size ? content.to_slice : content.chars)
      idx = skip_decorators_in(content, src, start_pos, dotted_decorator_names)
      return if idx > content.size
      name, open_paren = signature_head(content, src, idx) || return

      close_paren = matching_delimiter(content, src, open_paren, '(')
      return unless close_paren

      open_brace = index_of(content, src, '{', close_paren)
      return unless open_brace
      close_brace = matching_delimiter(content, src, open_brace, '{')

      {
        name:        name,
        params:      slice_of(content, src, open_paren + 1, close_paren),
        start_pos:   idx,
        open_paren:  open_paren,
        close_paren: close_paren,
        open_brace:  open_brace,
        close_brace: close_brace,
        body:        close_brace && close_brace > open_brace ? slice_of(content, src, open_brace + 1, close_brace) : nil,
      }
    end

    protected def body_from_signature(content : String, signature) : Tuple(String, Int32)?
      body = signature[:body]
      {body, signature[:open_brace]} if body
    end

    # `METHOD_SIGNATURE_AT` at char `idx`: the method name and its `(`.
    private def signature_head(content : String, src : Bytes, idx : Int32) : Tuple(String, Int32)?
      m = content.match(METHOD_SIGNATURE_AT, idx) || return
      {m[1], m.end(0) - 1}
    end

    # The pattern ends at the first `(` and holds none before it, so it is
    # matched on just the chars up to that `(`.
    private def signature_head(content : String, src : Array(Char), idx : Int32) : Tuple(String, Int32)?
      open_paren = index_of(content, src, '(', idx) || return
      m = slice_of(content, src, idx, open_paren + 1).match(METHOD_SIGNATURE_AT) || return
      {m[1], open_paren}
    end

    private def index_of(content : String, src : Bytes, char : Char, from : Int32) : Int32?
      content.index(char, from)
    end

    private def index_of(content : String, src : Array(Char), char : Char, from : Int32) : Int32?
      (from...src.size).find { |i| src.unsafe_fetch(i) == char }
    end

    private def slice_of(content : String, src : Bytes, from : Int32, to : Int32) : String
      content[from...to]
    end

    private def slice_of(content : String, src : Array(Char), from : Int32, to : Int32) : String
      String.build { |io| (from...to).each { |i| io << src.unsafe_fetch(i) } }
    end

    # A route decorator is often followed by more decorators before the
    # method itself — guards, interceptors, `@authenticate('jwt')`, custom
    # ones — so walk forward over any `@word(...)` / `@word` sequence.
    #
    # `src` indexes `content` by char: its bytes when it is ASCII, else its
    # `chars` (`content[i]` re-decodes UTF-8 from byte 0 on every call once
    # the string holds any non-ASCII char).
    private def skip_decorators_in(content : String, src, start_pos : Int32, dotted_names : Bool) : Int32
      idx = start_pos
      size = src.size
      loop do
        while idx < size && char_at(src, idx).whitespace?
          idx += 1
        end
        break if idx >= size || char_at(src, idx) != '@'

        name_end = idx + 1
        while name_end < size && ((c = char_at(src, name_end)).alphanumeric? || c == '_' || c == '$' || (dotted_names && c == '.'))
          name_end += 1
        end

        scan = name_end
        while scan < size && char_at(src, scan).whitespace?
          scan += 1
        end

        if scan < size && char_at(src, scan) == '('
          close = matching_delimiter(content, src, scan, '(')
          break unless close
          idx = close + 1
        else
          newline = content.index('\n', scan)
          idx = newline ? newline + 1 : size
        end
      end
      idx
    end

    private def matching_delimiter(content : String, src : Bytes, open : Int32, delimiter : Char) : Int32?
      delimiter == '(' ? Noir::JSRouteExtractor.find_matching_paren(content, open) : Noir::JSRouteExtractor.find_matching_brace(content, open)
    end

    private def matching_delimiter(content : String, src : Array(Char), open : Int32, delimiter : Char) : Int32?
      delimiter == '(' ? Noir::JSLiteralScanner.find_matching_paren(src, open) : Noir::JSLiteralScanner.find_matching_brace(src, open)
    end

    private def char_at(src : Bytes, i : Int32) : Char
      src.unsafe_fetch(i).unsafe_chr
    end

    private def char_at(src : Array(Char), i : Int32) : Char
      src.unsafe_fetch(i)
    end

    private def resolve_static_file_path(source_path : String, raw_path : String) : String
      normalized = raw_path.strip.gsub("\\", "/")
      return Noir::PathScope.expand(normalized) if normalized.starts_with?("/")

      source_dir = File.dirname(Noir::PathScope.expand(source_path))
      candidates = [] of String
      candidates << File.expand_path(normalized, source_dir)

      if project_root = nearest_js_project_root(source_dir)
        candidates << File.expand_path(normalized, project_root)
      end

      @base_paths.each do |base|
        candidates << File.expand_path(normalized, base)
      end

      candidates.uniq!
      candidates.find { |candidate| Dir.exists?(candidate) || File.exists?(candidate) } || candidates.first
    end

    private def nearest_js_project_root(start_dir : String) : String?
      dir = Noir::PathScope.expand(start_dir)
      bases = @base_paths.map do |base|
        expanded_base = Noir::PathScope.expand(base)
        expanded_base == "/" ? expanded_base : expanded_base.rstrip('/')
      end

      loop do
        return dir if JS_PROJECT_ROOT_MARKERS.any? { |marker| File.exists?(File.join(dir, marker)) }
        break if bases.includes?(dir)

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end

      nil
    end

    private def add_project_root(roots : Array(String), root : String) : Nil
      expanded = Noir::PathScope.expand(root)
      expanded = expanded.rstrip('/') unless expanded == "/"
      roots << expanded unless roots.includes?(expanded)
    end
  end
end
