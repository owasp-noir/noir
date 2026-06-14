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
    HTTP_METHODS    = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    PAGE_EXTENSIONS = [".svelte", ".svx", ".md"]
    API_EXTENSIONS  = [".ts", ".js", ".mjs"]
    EXTENSIONS      = PAGE_EXTENSIONS + API_EXTENSIONS

    FALLBACK_API_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      project_roots = discover_js_project_roots(
        ["@sveltejs/kit", "\"svelte-kit\""],
        ["svelte.config.js", "svelte.config.ts", "svelte.config.mjs", "svelte.config.cjs"]
      )

      parallel_file_scan(EXTENSIONS) do |path|
        next unless path_under_project_roots?(path, project_roots)
        idx = path.index("/src/routes/")
        next if idx.nil?

        relative = path[(idx + "/src/routes/".size)..-1]
        leaf = File.basename(relative)
        next if private_segment_in?(relative)

        if page_file?(leaf)
          analyze_page(path, relative, result, mutex)
        elsif page_server_file?(leaf)
          analyze_page_server(path, relative, result, mutex)
        elsif server_file?(leaf)
          analyze_api_route(path, relative, result, mutex, include_callee)
        end
      end

      result
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

    private def analyze_page(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      url = url_for(relative)
      endpoint = build_endpoint(url, "GET", path)
      mutex.synchronize { result << endpoint }
    end

    # `+page.server.{js,ts}` may export `actions` — SvelteKit form
    # actions, which are inbound POST handlers at the page's own URL
    # (the default action posts to the page, named actions to `?/name`).
    # These are the primary write surface of a SvelteKit app and are
    # distinct from the page's GET (emitted by the `+page.svelte`
    # sibling), so emit a POST. `load`-only `+page.server` files add no
    # endpoint of their own.
    private def analyze_page_server(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      content = begin
        read_file_content(path)
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end
      return unless form_actions?(content)

      url = url_for(relative)
      line = form_actions_line(content) || 1
      endpoint = build_endpoint(url, "POST", path, line)
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

    private def analyze_api_route(path : String, relative : String, result : Array(Endpoint), mutex : Mutex, include_callee : Bool)
      url = url_for(relative)
      content = begin
        read_file_content(path)
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end

      methods = detect_api_methods(content)
      endpoints = methods.map do |verb|
        endpoint = build_endpoint(url, verb, path, api_method_line(content, verb) || 1)
        attach_callees(endpoint, path, content, verb) if include_callee
        endpoint
      end

      mutex.synchronize do
        endpoints.each { |endpoint| result << endpoint }
      end
    end

    private def build_endpoint(url : String, verb : String, path : String, line : Int32 = 1) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      endpoint
    end

    # Convert filesystem-relative path under `src/routes/` to URL.
    # Drops the `+page.*` / `+server.*` leaf, hides `(group)` dirs,
    # and translates `[id]` / `[...slug]` to `{id}` / `{slug}`.
    private def url_for(relative : String) : String
      segments = relative.split("/").reject(&.empty?)
      segments.pop # remove the +page.* / +server.* leaf
      segments = segments.reject { |seg| group_segment?(seg) }
      mapped = segments.map { |seg| convert_segment(seg) }
      url = "/" + mapped.join("/")
      url = "/" if url == "/" || url.empty?
      url.sub(/\/+$/, "").presence || "/"
    end

    private def group_segment?(seg : String) : Bool
      seg.starts_with?("(") && seg.ends_with?(")")
    end

    # SvelteKit param group inside a route segment. Replaced in place so
    # one segment can hold static text around it (`foo-[id]`, `@[user]`)
    # and so every form normalizes to `{name}`:
    #   [id]  [id=int]  [...rest]  [[opt]]  [[opt=int]]  [[...rest]]
    PARAM_GROUP_RE = /\[+(?:\.{3})?(\w+)(?:=\w+)?\]+/

    private def convert_segment(seg : String) : String
      seg.gsub(PARAM_GROUP_RE) { "{#{$1}}" }
    end

    # Compiled once per verb — interpolated regex literals would otherwise
    # be rebuilt (full PCRE2 compile) for every method on every file.
    EXPORT_FUNCTION_RES = HTTP_METHODS.map { |m| {m, /export\s+(?:async\s+)?function\s+#{m}\b/} }.to_h
    EXPORT_CONST_RES    = HTTP_METHODS.map { |m| {m, /export\s+(?:const|let|var)\s+#{m}\b\s*(?::[^=]+)?=/} }.to_h
    EXPORT_BRACE_RES    = HTTP_METHODS.map { |m| {m, /export\s+\{\s*[^}]*\b#{m}\b[^}]*\}/} }.to_h

    private def detect_api_methods(content : String) : Array(String)
      explicit = [] of String
      HTTP_METHODS.each do |m|
        if content.match(EXPORT_FUNCTION_RES[m]) ||
           content.match(EXPORT_CONST_RES[m]) ||
           content.match(EXPORT_BRACE_RES[m])
          explicit << m
        end
      end
      explicit.empty? ? FALLBACK_API_METHODS : explicit
    end

    private def api_method_line(content : String, verb : String) : Int32?
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

    private def line_for_match(content : String, match : Regex::MatchData) : Int32
      start = match.begin(0) || 0
      content.to_slice[0, start].count('\n'.ord.to_u8) + 1
    end

    private def attach_callees(endpoint : Endpoint, path : String, content : String, verb : String)
      Noir::JSCalleeExtractor.callees_for_exported_function(content, path, verb).each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end
  end
end
