require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Astro is a filesystem-routed framework. Routes live under
  # `src/pages/` and the URL is derived from the file path:
  #
  #   src/pages/index.astro                → GET /
  #   src/pages/about.astro                → GET /about
  #   src/pages/users/index.astro          → GET /users
  #   src/pages/users/[id].astro           → GET /users/{id}
  #   src/pages/[...slug].astro            → GET /{slug}     (catch-all)
  #   src/pages/api/users.ts               → exports drive verbs
  #
  # Page files (`.astro`, `.md`, `.mdx`, `.html`) are HTML pages —
  # always GET. API route files in `src/pages/api/**` (`.ts`, `.js`,
  # `.mjs`, `.tsx`, `.jsx`) export named verb handlers
  # (`export async function GET(...)`, `export const POST = ...`).
  # When no explicit verb export is found we fall back to the
  # standard handler set (GET / POST / PUT / DELETE / PATCH) — same
  # heuristic the Next.js analyzer uses for catch-all handlers.
  #
  # Out of scope for this first cut:
  #   * Astro endpoints under non-conventional `src/pages/` roots
  #     (the path detection is hard-coded to `/src/pages/`).
  #   * Per-handler request-helper scanning — Astro endpoints use
  #     standard `Request` (`request.headers.get(...)`,
  #     `request.json()`, `await request.formData()`) but resolving
  #     reads accurately needs cross-call value tracking. Path
  #     placeholders still surface via the optimizer.
  class Astro < JavascriptEngine
    HTTP_METHODS    = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    PAGE_EXTENSIONS = [".astro", ".md", ".mdx", ".html"]
    API_EXTENSIONS  = [".ts", ".js", ".mjs", ".tsx", ".jsx"]
    EXTENSIONS      = PAGE_EXTENSIONS + API_EXTENSIONS

    # Lowest-cost defaults for endpoints whose handler doesn't
    # advertise its verbs explicitly. Mirrors the Next.js fallback.
    FALLBACK_API_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan(EXTENSIONS) do |path|
        idx = path.index("/src/pages/")
        next if idx.nil?

        relative = path[(idx + "/src/pages/".size)..-1]
        # Skip private files / dirs (`_` prefix) and Astro components
        # nested under non-pages directories like `src/pages/_partials`.
        next if relative.split("/").any?(&.starts_with?("_"))

        if api_route_file?(relative)
          analyze_api_route(path, relative, result, mutex)
        elsif page_file?(relative)
          analyze_page(path, relative, result, mutex)
        end
      end

      result
    end

    private def page_file?(relative : String) : Bool
      PAGE_EXTENSIONS.any? { |ext| relative.ends_with?(ext) }
    end

    private def api_route_file?(relative : String) : Bool
      relative.starts_with?("api/") && API_EXTENSIONS.any? { |ext| relative.ends_with?(ext) }
    end

    private def analyze_page(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      url = url_for(relative)
      endpoint = build_endpoint(url, "GET", path)
      mutex.synchronize { result << endpoint }
    end

    private def analyze_api_route(path : String, relative : String, result : Array(Endpoint), mutex : Mutex)
      url = url_for(relative)

      content = begin
        read_file_content(path)
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

    # Filesystem path → URL pattern. Strips the file extension,
    # collapses `/index` into the parent, and converts `[id]` /
    # `[...slug]` into `{id}` / `{slug}`.
    private def url_for(relative : String) : String
      stripped = strip_extension(relative)
      segments = stripped.split("/").reject(&.empty?).map { |seg| convert_segment(seg) }
      url = "/" + segments.join("/")
      url = url.sub(/\/index$/, "")
      url = "/" if url.empty?
      url
    end

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_segment(seg : String) : String
      # Catch-all: `[...slug]` or optional `[[...slug]]`
      if m = seg.match(/^\[+\.{3}(\w+)\]+$/)
        return "{#{m[1]}}"
      end
      # Dynamic: `[id]`
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    # Look for explicit verb exports first
    # (`export const GET = ...` / `export async function POST() {}`),
    # then fall back to the cross-method catch-all set.
    private def detect_api_methods(content : String) : Array(String)
      explicit = [] of String
      HTTP_METHODS.each do |m|
        # `export async function GET(...)`, `export function GET(...)`,
        # `export const GET = ...`, `export const GET: APIRoute = ...`
        # (the trailing TypeScript type annotation is optional), and
        # the `export { GET }` re-export form.
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
