require "../../engines/javascript_engine"

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

      parallel_file_scan(EXTENSIONS) do |path|
        idx = path.index("/src/routes/")
        next if idx.nil?

        relative = path[(idx + "/src/routes/".size)..-1]
        leaf = File.basename(relative)
        next if private_segment_in?(relative)

        if page_file?(leaf)
          analyze_page(path, relative, result, mutex)
        elsif server_file?(leaf)
          analyze_api_route(path, relative, result, mutex)
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

    private def analyze_page(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      url = url_for(relative)
      endpoint = build_endpoint(url, "GET", path)
      mutex.synchronize { result << endpoint }
    end

    private def analyze_api_route(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      url = url_for(relative)
      content = begin
        File.read(path, encoding: "utf-8", invalid: :skip)
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end

      methods = detect_api_methods(content)
      mutex.synchronize do
        methods.each do |verb|
          result << build_endpoint(url, verb, path)
        end
      end
    end

    private def build_endpoint(url : String, verb : String, path : String) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, 1))
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

    private def convert_segment(seg : String) : String
      # Optional + rest segments (`[[...slug]]` / `[...slug]`).
      if m = seg.match(/^\[+\.{3}(\w+)\]+$/)
        return "{#{m[1]}}"
      end
      # Dynamic `[id]` (and `[id=matcher]` — strip the matcher).
      if m = seg.match(/^\[(\w+)(?:=\w+)?\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def detect_api_methods(content : String) : Array(String)
      explicit = [] of String
      HTTP_METHODS.each do |m|
        if content.match(/export\s+(?:async\s+)?function\s+#{m}\b/) ||
           content.match(/export\s+(?:const|let|var)\s+#{m}\b\s*(?::[^=]+)?=/) ||
           content.match(/export\s+\{\s*[^}]*\b#{m}\b[^}]*\}/)
          explicit << m
        end
      end
      explicit.empty? ? FALLBACK_API_METHODS : explicit
    end
  end
end
