require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"

module Analyzer::Javascript
  # SvelteKit is a filesystem-routed framework. Routes live under
  # `src/routes/` and the URL is derived from the directory layout:
  #
  #   src/routes/+page.svelte                → GET /
  #   src/routes/about/+page.svelte          → GET /about
  #   src/routes/users/[id]/+page.svelte     → GET /users/{id}
  #   src/routes/users/+server.ts            → exports drive verbs
  #   src/routes/[...slug]/+page.svelte      → GET /{slug}
  #   src/routes/(group)/foo/+page.svelte    → GET /foo (group hidden)
  #
  # Two file kinds matter:
  #
  #   * `+page.svelte` (and the `.svx` / `.md` variants) — HTML
  #     pages, always GET. `+page.server.{js,ts}` siblings don't
  #     add a separate route — they're load functions for the same
  #     URL.
  #   * `+server.{js,ts,mjs}` — API endpoints. Each named verb
  #     export (`export async function GET`, `export const POST =
  #     ...`) registers a route. Falls back to GET / POST / PUT /
  #     DELETE / PATCH when no explicit verb is found, mirroring
  #     the Astro / Next.js heuristic.
  #
  # Out of scope for this first cut: per-handler request-helper
  # scanning (SvelteKit endpoints take `{ request, params, cookies,
  # url }` — accurate read tracking needs cross-call value flow),
  # rest parameters with matchers (`[id=integer]`), and
  # `(group)`-with-`+layout.server.ts` cookie-protected endpoints
  # (the route still fires; auth tagging is the tagger's job).
  class Sveltekit < JavascriptEngine
    analyzer_for "js_sveltekit"

    PAGE_EXTENSIONS = [".svelte", ".svx", ".md"]
    API_EXTENSIONS  = [".ts", ".js", ".mjs"]
    EXTENSIONS      = PAGE_EXTENSIONS + API_EXTENSIONS

    CONFIG_BASENAMES = ["svelte.config.js", "svelte.config.ts", "svelte.config.mjs", "svelte.config.cjs"]

    # `kit: { paths: { base: '/x' } }`, literal strings only: an env lookup
    # or interpolated template has no value to read statically.
    PATHS_BASE_RE = /\bpaths\s*:\s*\{[^}]*?\bbase\s*:\s*(['"`])(\/[^'"`$]*)\1/

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      project_roots = discover_js_project_roots(["@sveltejs/kit", "\"svelte-kit\""], CONFIG_BASENAMES)

      # `src/routes/` must sit directly in a project root: a sample app nested
      # below a real one (docs tutorial overlays, test fixtures) is not served.
      # Each maps to the root's `kit.paths.base`, which prefixes every route.
      route_dirs = project_roots.to_h { |root| {File.join(root, "src/routes/"), paths_base(root)} }

      parallel_file_scan(EXTENSIONS) do |path|
        expanded = Noir::PathScope.expand(path)
        base = ""
        unless route_dirs.empty?
          dir = route_dirs.keys.find { |route_dir| expanded.starts_with?(route_dir) } || next
          base = route_dirs[dir]
        end
        relative = src_routes_relative(path) || next
        leaf = File.basename(relative)
        next if private_segment_in?(relative)

        if page_file?(leaf)
          analyze_page(path, url_for(relative, base), result, mutex)
        elsif page_server_file?(leaf)
          analyze_page_server(path, url_for(relative, base), result, mutex)
          analyze_page_module(path, url_for(relative, base), result, mutex)
        elsif page_load_file?(leaf)
          analyze_page_module(path, url_for(relative, base), result, mutex)
        elsif server_file?(leaf)
          analyze_api_route(path, url_for(relative, base), result, mutex, include_callee)
        end
      end

      result
    end

    private def paths_base(root : String) : String
      CONFIG_BASENAMES.each do |name|
        config = File.join(root, name)
        next unless File.file?(config)
        content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(config))
        if match = content.match(PATHS_BASE_RE)
          return match[2].rstrip('/')
        end
      rescue IO::Error
        next
      end
      ""
    end

    private def private_segment_in?(relative : String) : Bool
      # SvelteKit treats `_foo` directories as private (excluded from
      # routing). `(group)` directories are public but stripped from
      # the URL — they're handled in the URL builder.
      relative.split("/").any?(&.starts_with?("_"))
    end

    private def page_file?(leaf : String) : Bool
      return false unless leaf.starts_with?("+page")
      PAGE_EXTENSIONS.any? { |ext| leaf.ends_with?(ext) }
    end

    private def server_file?(leaf : String) : Bool
      return false unless leaf.starts_with?("+server")
      API_EXTENSIONS.any? { |ext| leaf.ends_with?(ext) }
    end

    private def page_server_file?(leaf : String) : Bool
      return false unless leaf.starts_with?("+page.server")
      API_EXTENSIONS.any? { |ext| leaf.ends_with?(ext) }
    end

    # `+page.js` / `+page.ts`: the universal `load` of a page.
    private def page_load_file?(leaf : String) : Bool
      API_EXTENSIONS.any? { |ext| leaf == "+page#{ext}" }
    end

    # A page with only a `+page.js` / `+page.server.ts` (usually a `load`
    # that redirects) still answers GET; with a `+page.svelte` sibling that
    # sibling reports it.
    private def analyze_page_module(path : String, url : String, result : Array(Endpoint), mutex : Mutex)
      dir = File.dirname(path)
      return if PAGE_EXTENSIONS.any? { |ext| File.exists?(File.join(dir, "+page#{ext}")) }
      analyze_page(path, url, result, mutex)
    end

    private def analyze_page(path : String, url : String, result : Array(Endpoint), mutex : Mutex)
      endpoint = file_route_endpoint(url, "GET", path)
      mutex.synchronize { result << endpoint }
    end

    # `+page.server.{js,ts}` may export `actions` — SvelteKit form
    # actions, which are inbound POST handlers at the page's own URL
    # (the default action posts to the page, named actions to `?/name`).
    # These are the primary write surface of a SvelteKit app and are
    # distinct from the page's GET (emitted by the `+page.svelte`
    # sibling), so emit a POST. `load`-only `+page.server` files add no
    # endpoint of their own.
    private def analyze_page_server(path : String, url : String, result : Array(Endpoint), mutex : Mutex)
      # Comments blanked in place (line numbers kept), so a commented-out
      # export is not a route.
      content = begin
        Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end
      return unless form_actions?(content)

      line = form_actions_line(content) || 1
      endpoint = file_route_endpoint(url, "POST", path, line)
      mutex.synchronize { result << endpoint }
    end

    private def form_actions?(content : String) : Bool
      content.matches?(FORM_ACTIONS_DECL_RE) ||
        content.matches?(/export\s+\{\s*[^}]*\bactions\b[^}]*\}/)
    end

    FORM_ACTIONS_DECL_RE = /export\s+(?:const|let|var|(?:async\s+)?function)\s+actions\b/

    private def form_actions_line(content : String) : Int32?
      if match = content.match(FORM_ACTIONS_DECL_RE)
        return line_for_match(content, match)
      end
      nil
    end

    private def analyze_api_route(path : String, url : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      # Comments blanked in place (line numbers kept), so a commented-out
      # export is not a route.
      content = begin
        Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end

      methods = detect_api_methods(content)
      endpoints = methods.map do |verb|
        endpoint = file_route_endpoint(url, verb, path, api_method_line(content, verb) || 1)
        attach_callees(endpoint, path, content, verb) if include_callee
        endpoint
      end

      mutex.synchronize do
        endpoints.each { |endpoint| result << endpoint }
      end
    end

    # Drops the `+page.*` / `+server.*` leaf; the root route of a based app
    # is the bare base (`/greenhouse`, not `/greenhouse/`).
    private def url_for(relative : String, base : String) : String
      url = file_route_url(relative.split('/')[0...-1])
      return url if base.empty?
      url == "/" ? base : base + url
    end

    private def attach_callees(endpoint : Endpoint, path : String, content : String, verb : String)
      Noir::JSCalleeExtractor.callees_for_exported_function(content, path, verb).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end
  end
end
