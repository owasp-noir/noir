require "../../engines/javascript_engine"

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
    HTTP_METHODS    = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    PAGE_EXTENSIONS = [".tsx", ".jsx"]
    API_EXTENSIONS  = [".ts", ".js", ".mjs"]
    EXTENSIONS      = PAGE_EXTENSIONS + API_EXTENSIONS

    FALLBACK_HANDLER_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Files that are framework plumbing rather than routes.
    SKIPPED_LEAFS = ["_app", "_layout", "_404", "_500", "_middleware"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan(EXTENSIONS) do |path|
        idx = path.index("/routes/")
        next if idx.nil?

        relative = path[(idx + "/routes/".size)..-1]
        leaf = strip_extension(File.basename(relative))
        next if SKIPPED_LEAFS.includes?(leaf)
        next if leaf.starts_with?("_") # other underscore-prefixed plumbing

        url = url_for(relative)

        content = begin
          File.read(path, encoding: "utf-8", invalid: :skip)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        is_page = PAGE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        verbs = detect_verbs(content, is_page)
        next if verbs.empty?

        mutex.synchronize do
          verbs.each { |verb| result << build_endpoint(url, verb, path) }
        end
      end

      result
    end

    private def build_endpoint(url : String, verb : String, path : String) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, 1))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      endpoint
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

    private def detect_verbs(content : String, is_page : Bool) : Array(String)
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
      if handler_block = extract_handler_object(content)
        keys = extract_verb_keys(handler_block)
        verbs.concat(keys) unless keys.empty?
      elsif handler_function?(content)
        # `export const handler = (req, ctx) => ...` or
        # `export function handler(req)` — a single function
        # answers every method.
        verbs.concat(FALLBACK_HANDLER_METHODS)
      end

      verbs.uniq
    end

    private def has_default_export?(content : String) : Bool
      content.match(/export\s+default\b/) != nil
    end

    # Carve the `{...}` object literal out of `export const handler =
    # { ... }` (or `: Handlers = {...}`). Returns nil when the
    # handler is a function, a callable reference, or absent.
    private def extract_handler_object(content : String) : String?
      m = content.match(/export\s+(?:const|let|var)\s+handler\b\s*(?::[^=]+)?=\s*(\{)/)
      return unless m
      after_match = m.byte_end(0)
      return unless after_match
      open_idx = after_match - 1
      close_idx = match_braces(content, open_idx)
      return unless close_idx
      content.byte_slice(open_idx, close_idx - open_idx + 1)
    end

    private def handler_function?(content : String) : Bool
      content.match(/export\s+(?:async\s+)?function\s+handler\b/) != nil ||
        content.match(/export\s+(?:const|let|var)\s+handler\b\s*(?::[^=]+)?=\s*(?:async\s*)?(?:function\b|\()/) != nil
    end

    # Extract the verb names appearing as object keys inside the
    # handler block. Two shapes:
    #
    #   GET(req, ctx) { ... }              (method shorthand)
    #   GET: (req, ctx) => { ... }         (property assignment)
    #
    # `async` prefix is allowed on the shorthand; the trailing
    # value can be a function expression, arrow function, or
    # callable reference.
    private def extract_verb_keys(block : String) : Array(String)
      verbs = [] of String
      HTTP_METHODS.each do |m|
        if block.match(/(^|[\{,\s])(?:async\s+)?#{m}\s*\(/) ||
           block.match(/(^|[\{,\s])#{m}\s*:/)
          verbs << m
        end
      end
      verbs
    end

    # Walk `content` from the opening `{` at `start` and return the
    # index of the matching `}`. Tolerates nested braces; returns
    # nil when the file is unbalanced.
    private def match_braces(content : String, start : Int32) : Int32?
      depth = 0
      i = start
      bytes = content.to_slice
      while i < bytes.size
        case bytes[i]
        when '{'.ord
          depth += 1
        when '}'.ord
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end
  end
end
