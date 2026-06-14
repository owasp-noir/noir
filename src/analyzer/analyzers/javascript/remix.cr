require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"

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
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

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
          read_file_content(path)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        is_page = PAGE_EXTENSIONS.any? { |ext| relative.ends_with?(ext) }
        has_loader = export_named?(content, "loader")
        has_action = export_named?(content, "action")
        verbs = detect_verbs(is_page, has_loader, has_action)
        next if verbs.empty?

        loader_line = has_loader ? exported_handler_line(content, "loader") : nil
        action_line = has_action ? exported_handler_line(content, "action") : nil
        loader_callees = include_callee && has_loader ? Noir::JSCalleeExtractor.callees_for_exported_function(content, path, "loader") : nil
        action_callees = include_callee && has_action ? Noir::JSCalleeExtractor.callees_for_exported_function(content, path, "action") : nil

        endpoints = verbs.map do |verb|
          endpoint_line = verb == "GET" ? (loader_line || 1) : (action_line || 1)
          endpoint = build_endpoint(url, verb, path, endpoint_line)
          if include_callee
            callees = verb == "GET" ? loader_callees : action_callees
            callees.try &.each do |name, callee_path, callee_line|
              endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
            end
          end
          endpoint
        end

        mutex.synchronize do
          endpoints.each { |endpoint| result << endpoint }
        end
      end

      result
    end

    private def build_endpoint(url : String, verb : String, path : String, line : Int32 = 1) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.details = Details.new(PathInfo.new(path, line))
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
      raw_segments = split_flat_segments(name)
      segments = [] of String
      raw_segments.each do |seg|
        next if seg == "_index"       # blends with parent URL
        next if seg.starts_with?("_") # pathless layout
        if seg == "$"
          segments << "{splat}"
        elsif seg.starts_with?("$")
          segments << "{#{normalize_segment(seg[1..])}}"
        elsif seg.starts_with?("(") && seg.ends_with?(")")
          # Optional segment — surface the inner literal / dynamic
          # so reviewers can still see the route, even though the
          # alternative-without is lossy.
          inner = seg[1..-2]
          if inner.starts_with?("$")
            segments << "{#{normalize_segment(inner[1..])}}"
          else
            segments << normalize_segment(inner)
          end
        else
          segments << normalize_segment(seg)
        end
      end

      url = "/" + segments.join("/")
      url == "/" ? "/" : url.sub(/\/+$/, "")
    end

    # Split a dot-flat Remix route name on segment separators, treating a
    # `.` inside an escaped `[...]` group as a literal (e.g.
    # `jokes[.]rss` is ONE segment whose URL is `/jokes.rss`, not two).
    private def split_flat_segments(name : String) : Array(String)
      segments = [] of String
      current = String::Builder.new
      depth = 0
      name.each_char do |ch|
        case ch
        when '['
          depth += 1
          current << ch
        when ']'
          depth -= 1 if depth > 0
          current << ch
        when '.'
          if depth == 0
            segments << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end
      segments << current.to_s
      segments
    end

    # Unescape `[...]` literals (the brackets are removed; their contents
    # are taken verbatim) and drop a single trailing `_` — Remix's
    # "opt out of parent layout" marker, which never affects the URL or a
    # param name (`$contactId_` -> `contactId`, `sitemap[.]xml` ->
    # `sitemap.xml`).
    private def normalize_segment(seg : String) : String
      unescaped = seg.delete('[').delete(']')
      unescaped.ends_with?("_") ? unescaped[0...-1] : unescaped
    end

    # `verbs(is_page, has_loader, has_action)` — figure out which verbs the file
    # registers based on the page-vs-resource shape and the
    # exported names.
    private def detect_verbs(is_page : Bool, has_loader : Bool, has_action : Bool) : Array(String)
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
      # `name` is "loader" / "action" — memoized so the three patterns
      # compile once per scan instead of once per file.
      content.matches?(cached_regex("remix:export_fn:#{name}") { /export\s+(?:async\s+)?function\s+#{name}\b/ }) ||
        content.matches?(cached_regex("remix:export_const:#{name}") { /export\s+(?:const|let|var)\s+#{name}\b\s*(?::[^=]+)?=/ }) ||
        content.matches?(cached_regex("remix:export_brace:#{name}") { /export\s+\{\s*[^}]*\b#{name}\b[^}]*\}/ })
    end

    private def exported_handler_line(content : String, name : String) : Int32?
      if match = content.match(cached_regex("remix:line_export_fn:#{name}") { /export\s+(?:async\s+)?function\s+#{Regex.escape(name)}\b/ })
        return line_for_match(content, match)
      end

      if match = content.match(cached_regex("remix:line_export_const:#{name}") { /export\s+(?:const|let|var)\s+#{Regex.escape(name)}\b\s*(?::[^=]+)?=/ })
        return line_for_match(content, match)
      end

      if local_name = exported_alias_for(content, name)
        named_handler_line(content, local_name)
      end
    end

    private def exported_alias_for(content : String, exported_name : String) : String?
      content.scan(/export\s+\{\s*([^}]+)\}/) do |match|
        match[1].split(",").each do |part|
          pieces = part.strip.split(/\s+as\s+/)
          next if pieces.empty?

          if pieces.size == 1
            local_name = pieces[0].strip
            return local_name if local_name == exported_name
          elsif pieces.size == 2
            local_name = pieces[0].strip
            alias_name = pieces[1].strip
            return local_name if alias_name == exported_name
          end
        end
      end
    end

    private def named_handler_line(content : String, name : String) : Int32?
      if match = content.match(cached_regex("remix:line_named_fn:#{name}") { /\b(?:async\s+)?function\s+#{Regex.escape(name)}\b/ })
        return line_for_match(content, match)
      end

      if match = content.match(cached_regex("remix:line_named_const:#{name}") { /\b(?:const|let|var)\s+#{Regex.escape(name)}\b\s*(?::[^=]+)?=/ })
        line_for_match(content, match)
      end
    end

    private def line_for_match(content : String, match : Regex::MatchData) : Int32
      start = match.begin(0) || 0
      content.to_slice[0, start].count('\n'.ord.to_u8) + 1
    end
  end
end
