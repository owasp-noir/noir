require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Remix v2 is filesystem-routed under `app/routes/`. The route URL
  # is derived from the filename via dot-flat naming and a handful
  # of special prefixes:
  #
  #   app/routes/_index.tsx          → GET /
  #   app/routes/about.tsx           → GET /about
  #   app/routes/users._index.tsx    → GET /users
  #   app/routes/users.$id.tsx       → GET /users/{id}
  #   app/routes/_auth.login.tsx     → GET /login   (`_auth` is a
  #                                                  pathless layout
  #                                                  — no URL effect)
  #   app/routes/api.users.ts        → exports drive verbs
  #   app/routes/$.tsx               → catch-all
  #
  # Verb detection:
  #
  #   * `.tsx` / `.jsx` files render a page — emit GET.
  #   * Files exporting `loader` add GET (or keep it).
  #   * Files exporting `action` add POST / PUT / PATCH / DELETE
  #     (Remix dispatches every non-GET to `action` at runtime;
  #     we surface the full set so downstream tooling can fan out).
  #   * Resource-only `.ts` / `.js` files without `loader` or
  #     `action` are skipped — they're not handler routes.
  #
  # Out of scope for this first cut:
  #
  #   * Per-handler request-helper scanning. Remix loaders / actions
  #     receive `{ request, params, context }` — accurate read
  #     tracking needs cross-call value flow. Path placeholders
  #     still surface via the optimizer.
  #   * Optional segments `($lang)` (translated to a literal `lang`
  #     today; Remix folds optionality into a wildcard match that's
  #     hard to represent without per-route alternatives).
  #   * The legacy v1 nested-folder convention — v2 flat is what
  #     the toolchain has been on since Remix 1.15 / Remix 2.
  class Remix < JavascriptEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    PAGE_EXTENSIONS     = [".tsx", ".jsx"]
    RESOURCE_EXTENSIONS = [".ts", ".js", ".mjs"]
    EXTENSIONS          = PAGE_EXTENSIONS + RESOURCE_EXTENSIONS

    NON_GET_VERBS = ["POST", "PUT", "PATCH", "DELETE"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan(EXTENSIONS) do |path|
        idx = path.index("/app/routes/")
        next if idx.nil?

        relative = path[(idx + "/app/routes/".size)..-1]
        # Remix only looks at the directly-named route file. Files
        # nested deeper inside a route's directory (`route.tsx` /
        # subcomponents) are component wiring, not route hosts.
        next if relative.includes?("/")

        leaf = strip_extension(relative)
        next if leaf.empty?

        url = url_for(leaf)

        content = begin
          File.read(path, encoding: "utf-8", invalid: :skip)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        is_page = PAGE_EXTENSIONS.any? { |ext| relative.ends_with?(ext) }
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

    # Translate a dot-flat Remix route name to a URL pattern.
    # Segments split on `.`; `_` prefixes mark pathless layouts;
    # `$slug` becomes `{slug}`; bare `$` is the catch-all sentinel;
    # `_index` collapses to the parent URL.
    private def url_for(name : String) : String
      raw_segments = name.split(".")
      segments = [] of String
      raw_segments.each do |seg|
        next if seg == "_index"       # blends with parent URL
        next if seg.starts_with?("_") # pathless layout
        if seg == "$"
          segments << "{splat}"
        elsif seg.starts_with?("$")
          segments << "{#{seg[1..]}}"
        elsif seg.starts_with?("(") && seg.ends_with?(")")
          # Optional segment — surface the inner literal / dynamic
          # so reviewers can still see the route, even though the
          # alternative-without is lossy.
          inner = seg[1..-2]
          if inner.starts_with?("$")
            segments << "{#{inner[1..]}}"
          else
            segments << inner
          end
        else
          segments << seg
        end
      end

      url = "/" + segments.join("/")
      url == "/" ? "/" : url.sub(/\/+$/, "")
    end

    # `verbs(content, is_page)` — figure out which verbs the file
    # registers based on the page-vs-resource shape and the
    # exported names.
    private def detect_verbs(content : String, is_page : Bool) : Array(String)
      has_loader = export_named?(content, "loader")
      has_action = export_named?(content, "action")

      verbs = [] of String
      verbs << "GET" if is_page || has_loader
      verbs.concat(NON_GET_VERBS) if has_action

      # Resource files (`.ts` / `.js`) without `loader` or `action`
      # aren't routes — they're shared utilities. Remix does pick up
      # the bare default export (`headers`, `meta`, etc.) but those
      # don't fire as request handlers.
      verbs.uniq
    end

    private def export_named?(content : String, name : String) : Bool
      content.match(/export\s+(?:async\s+)?function\s+#{name}\b/) != nil ||
        content.match(/export\s+(?:const|let|var)\s+#{name}\b\s*(?::[^=]+)?=/) != nil ||
        content.match(/export\s+\{\s*[^}]*\b#{name}\b[^}]*\}/) != nil
    end
  end
end
