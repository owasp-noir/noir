require "../../engines/javascript_engine"
require "../../../miniparsers/js_handler_table"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  # Fresh is Deno's filesystem-routed framework. Routes live under
  # `routes/` and the URL is derived from the directory layout:
  #
  #   routes/index.tsx               → GET /
  #   routes/about.tsx               → GET /about
  #   routes/users/index.tsx         → GET /users
  #   routes/users/[id].tsx          → GET /users/{id}
  #   routes/api/users.ts            → handler-driven verbs
  #   routes/[...slug].tsx           → GET /{slug}
  #
  # Verb shape:
  #
  #   * Page files (`.tsx` / `.jsx`) with a `export default`
  #     component render HTML — emit GET.
  #   * Resource files export a `handler` object whose keys
  #     are HTTP verbs:
  #
  #         export const handler: Handlers = {
  #             GET(req, ctx) { ... },
  #             async POST(req, ctx) { ... },
  #             PUT: async (req) => { ... },
  #         };
  #
  #     Each verb-shaped key (method shorthand or property
  #     assignment) registers a route.
  #   * If `handler` is a single function (no object), Fresh
  #     dispatches every method to it — fall back to the standard
  #     handler set (GET / POST / PUT / DELETE / PATCH).
  #
  # Underscore-prefixed files (`_app.tsx`, `_layout.tsx`,
  # `_404.tsx`, `_500.tsx`, `_middleware.ts`) are framework
  # plumbing — not user-facing routes — and skipped.
  #
  # Out of scope for this first cut:
  #
  #   * Per-handler request-helper scanning. Fresh handlers receive
  #     `(req, ctx)` — accurate read tracking needs cross-call
  #     value flow. Path placeholders still surface via the
  #     optimizer.
  #   * Route groups (`(group)` directories — same convention as
  #     SvelteKit). Add when fixtures show real-world usage.
  class Fresh < JavascriptEngine
    analyzer_for "js_fresh"

    HTTP_METHODS    = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    PAGE_EXTENSIONS = [".tsx", ".jsx"]
    API_EXTENSIONS  = [".ts", ".js", ".mjs"]
    EXTENSIONS      = PAGE_EXTENSIONS + API_EXTENSIONS

    FALLBACK_HANDLER_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Directories holding a Fresh project manifest. A bare `deno.json` is not
    # enough — a plain Deno project has one too — so it only counts when it
    # references `$fresh/`.
    private def fresh_project_roots : Array(String)
      roots = [] of String
      all_files.each do |file|
        base = File.basename(file)
        marked =
          if ROOT_CONFIG_BASENAMES.includes?(base)
            true
          elsif DENO_MANIFEST_BASENAMES.includes?(base)
            begin
              read_file_content(file).matches?(FRESH_IMPORT_MARKER)
            rescue
              false
            end
          else
            false
          end
        next unless marked
        root = Noir::PathScope.normalize_root(File.dirname(file))
        roots << root unless roots.includes?(root)
      end
      roots
    end

    # Files that are framework plumbing rather than routes.
    SKIPPED_LEAVES = ["_app", "_layout", "_404", "_500", "_middleware"]

    # Fresh's own default `ignore` for the routes tree (TEST_FILE_PATTERN in
    # `constants.ts`): `routes/foo.test.ts` and `routes/index_test.tsx` are
    # never served.
    TEST_FILE_PATTERN = /[._]test\.(?:[tj]sx?|[mc][tj]s)$/

    # A Fresh project is anchored by `fresh.config.{ts,js}`, or by a Deno
    # manifest that pulls in `$fresh/`. Same shape the detector already
    # treats as authoritative.
    ROOT_CONFIG_BASENAMES   = ["fresh.config.ts", "fresh.config.js", "fresh.config.mjs"]
    DENO_MANIFEST_BASENAMES = ["deno.json", "deno.jsonc"]
    # Fresh 1 maps `$fresh/`; Fresh 2 (`jsr:@fresh/init`) maps the bare
    # `fresh` specifier to `jsr:@fresh/core`.
    FRESH_IMPORT_MARKER = /\$fresh\/|@fresh\//
    # Fresh 2's programmatic router: `const app = new App()` imported from
    # `fresh`, then `app.get("/api2/:name", handler)` beside `app.fsRoutes()`.
    FRESH_APP_MARKER = /\bnew\s+App\b/
    FRESH_APP_IMPORT = /from\s+["'](?:fresh|jsr:@fresh\/core[^"']*|@fresh\/core)["']/

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      # `routes/` on its own is not a Fresh signal — Remix keeps its route
      # modules in `app/routes/`, and Koa/Express/Fastify projects routinely
      # have one too. Treating every `*/routes/*` in the scan as a Fresh
      # file-system route meant Remix's `users.$id.tsx` and `users._index.tsx`
      # surfaced as Fresh endpoints named after the file. Scope to the Fresh
      # project root the same way the SvelteKit and Nitro analyzers do; with
      # no marker found `path_under_project_roots?` waves everything through.
      project_roots = fresh_project_roots

      parallel_file_scan(EXTENSIONS) do |path|
        next unless path_under_project_roots?(path, project_roots)
        next if File.basename(path).matches?(TEST_FILE_PATTERN)
        # Scan-base-relative, never absolute: `String#index` takes the
        # FIRST occurrence, so a same-named directory above the scan base
        # won outright and the derived URL changed with the checkout path.
        scoped = base_relative_path(path)
        idx = scoped.index("/routes/")
        next if in_test_tree?(idx ? scoped[0...idx] : File.dirname(scoped))
        if idx.nil?
          app_routes = app_route_endpoints(path)
          mutex.synchronize { result.concat(app_routes) } unless app_routes.empty?
          next
        end

        relative = scoped[(idx + "/routes/".size)..-1]
        leaf = strip_extension(File.basename(relative))
        next if SKIPPED_LEAVES.includes?(leaf)
        next if leaf.starts_with?("_") # other underscore-prefixed plumbing

        url = url_for(relative)

        content = begin
          read_file_content(path)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        is_page = PAGE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        table = Noir::JSHandlerTable.for(content, path, callees_needed?)
        verbs = detect_verbs(content, table, is_page)
        next if verbs.empty?

        mutex.synchronize do
          verbs.each do |verb|
            endpoint = file_route_endpoint(url, verb, path)
            attach_handler_callees(endpoint, table, verb) if callees_needed?
            result << endpoint
          end
        end
      end

      result
    end

    # `app.get(path, handler)` on a Fresh 2 `App`; the verb-call shape is
    # the shared extractor's.
    private def app_route_endpoints(path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content.matches?(FRESH_APP_MARKER) && content.matches?(FRESH_APP_IMPORT)
      Noir::JSRouteExtractor.extract_routes(path, content, @is_debug, include_callees: callees_needed?).map do |endpoint|
        endpoint.url.scan(/:(\w+)/) { |m| endpoint.push_param(Param.new(m[1], "", "path")) }
        endpoint
      end
    end

    private def attach_handler_callees(endpoint : Endpoint, table : Noir::JSHandlerTable::Table, verb : String)
      callees = [table.exports[verb]?, table.objects["handler"]?.try(&.[verb]?), table.exports["handler"]?]
        .compact_map(&.try(&.callees)).find { |entries| !entries.empty? } || return
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    private def strip_extension(name : String) : String
      EXTENSIONS.each do |ext|
        return name[0..(name.size - ext.size - 1)] if name.ends_with?(ext)
      end
      name
    end

    # Filesystem path → URL pattern. Drops the file extension,
    # collapses `/index` into the parent, and translates
    # `[id]` / `[...slug]` to `{id}` / `{slug}`.
    private def url_for(relative : String) : String
      stripped = strip_extension(relative)
      segments = stripped.split("/").reject(&.empty?).map { |seg| convert_segment(seg) }
      url = "/" + segments.join("/")
      url = url.sub(/\/index$/, "")
      url = "/" if url.empty?
      url
    end

    private def convert_segment(seg : String) : String
      # Catch-all `[...slug]`.
      if m = seg.match(/^\[\.{3}(\w+)\]$/)
        return "{#{m[1]}}"
      end
      # Dynamic `[id]`.
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def detect_verbs(content : String, table : Noir::JSHandlerTable::Table, is_page : Bool) : Array(String)
      verbs = [] of String

      # Component-driven page → GET. The `export default` form is
      # the marker; some pages skip the React component entirely
      # in which case the file is a handler-only resource and gets
      # picked up below.
      if is_page && has_default_export?(content)
        verbs << "GET"
      end

      # Handler-driven verbs. Look for `export const handler` (with
      # optional type annotation) and pull verb-shaped keys out of
      # the trailing object literal.
      if members = table.objects["handler"]?
        verbs.concat(HTTP_METHODS.select { |verb| members.has_key?(verb) })
      elsif table.exports["handler"]?.try(&.direct)
        # `export const handler = (req, ctx) => ...` or
        # `export function handler(req)` — a single function
        # answers every method.
        verbs.concat(FALLBACK_HANDLER_METHODS)
      end

      verbs.uniq
    end

    private def has_default_export?(content : String) : Bool
      content.matches?(/export\s+default\b/)
    end
  end
end
