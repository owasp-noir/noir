require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../utils/top_level_split"

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
  #     (v2 folder routes — `routes/users.$id/route.tsx` — are read.)
  class Remix < JavascriptEngine
    analyzer_for "js_remix"

    PAGE_EXTENSIONS     = [".tsx", ".jsx"]
    RESOURCE_EXTENSIONS = [".ts", ".js", ".mjs"]
    EXTENSIONS          = PAGE_EXTENSIONS + RESOURCE_EXTENSIONS

    NON_GET_VERBS = ["POST", "PUT", "PATCH", "DELETE"]

    # A folder route's module: `routes/users.$id/route.tsx` (or `index.tsx`).
    FOLDER_ROUTE_MODULES = ["route", "index"]

    # A Remix project is anchored by `remix.config.*` or a package.json
    # pulling in a Remix v2 package. Scoping to it keeps Remix off a sibling
    # React Router app's `app/routes/`, which uses the same file convention.
    # Not the bare `@remix-run/` scope: React Router apps depend on
    # utilities published under it (`@remix-run/node-fetch-server`).
    PACKAGE_MARKERS = %w[dev react node serve server-runtime cloudflare cloudflare-pages cloudflare-workers deno express architect]
      .map { |name| %("@remix-run/#{name}") }
    CONFIG_BASENAMES = ["remix.config.js", "remix.config.ts", "remix.config.mjs", "remix.config.cjs"]

    # React Router v7's route config. Remix has none, so an app directory
    # holding one belongs to React Router even inside a Remix project root
    # (a monorepo whose root package.json hoists `@remix-run/dev`).
    ROUTE_CONFIG_BASENAMES = ["routes.ts", "routes.js", "routes.mts", "routes.mjs"]
    ROUTE_CONFIG_MARKER    = "@react-router/"

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      roots = project_roots
      react_router_dirs = react_router_apps

      parallel_file_scan(EXTENSIONS) do |path|
        next unless path_under_project_roots?(path, roots)
        next unless name = flat_route_name(path)
        next if (app = flat_route(Noir::PathScope.expand(path))) && react_router_dirs.has_key?(app[0])

        endpoints = module_endpoints(url_for(name), path, include_callee)
        mutex.synchronize { result.concat(endpoints) } if endpoints
      end

      result
    end

    private def project_roots : Array(String)
      discover_js_project_roots(PACKAGE_MARKERS, CONFIG_BASENAMES)
    end

    # Expanded app directory → the React Router route configs that build it.
    # A config inside another config's directory is a split-out part of that
    # app (`app/features/admin/routes.ts`), so its module paths resolve
    # against the outer app directory, not its own.
    private def react_router_apps : Hash(String, Array(String))
      configs = {} of String => String
      ROUTE_CONFIG_BASENAMES.each do |basename|
        get_files_by_basename(basename).each do |path|
          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end
          configs[path] = File.dirname(Noir::PathScope.expand(path)) if content.includes?(ROUTE_CONFIG_MARKER)
        end
      end

      apps = {} of String => Array(String)
      configs.each do |path, dir|
        app = configs.values.select { |root| Noir::PathScope.under_normalized_root?(dir, root) }.min_by(&.size)
        (apps[app] ||= [] of String) << path
      end
      apps
    end

    # Dot-flat route name of a module under `app/routes/`: a flat file
    # (`routes/users.$id.tsx`) or a folder route, whose module is the
    # folder's `route.tsx` / `index.tsx` (`routes/users.$id/route.tsx`).
    # Anything nested deeper is component wiring, not a route host.
    private def flat_route_name(path : String) : String?
      # Scan-base-relative, never absolute: an `app/` directory above the
      # scan base must not turn the tree under it into routes.
      flat_route(base_relative_path(path)).try do |app_dir, name|
        name if File.basename(app_dir) == "app"
      end
    end

    # `{app_dir, route_name}` for a module directly under `<app_dir>/routes/`.
    private def flat_route(path : String) : Tuple(String, String)?
      dir = File.dirname(path)
      name = strip_extension(File.basename(path))
      if File.basename(dir) != "routes" && FOLDER_ROUTE_MODULES.includes?(name)
        name = File.basename(dir)
        dir = File.dirname(dir)
      end
      return unless File.basename(dir) == "routes"
      return if name.empty?
      {File.dirname(dir), name}
    end

    # Endpoints one route module serves at `url`, or nil when it serves none
    # (a resource module without `loader` / `action`) or cannot be read.
    private def module_endpoints(url : String, path : String, include_callee : Bool) : Array(Endpoint)?
      content = begin
        read_file_content(path)
      rescue e
        logger.debug "Error reading #{path}: #{e.message}"
        return
      end

      is_page = PAGE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
      has_loader = export_named?(content, "loader")
      has_action = export_named?(content, "action")
      verbs = detect_verbs(is_page, has_loader, has_action)
      return if verbs.empty?

      loader_line = has_loader ? exported_handler_line(content, "loader") : nil
      action_line = has_action ? exported_handler_line(content, "action") : nil
      loader_callees = include_callee && has_loader ? Noir::JSCalleeExtractor.callees_for_exported_function(content, path, "loader") : nil
      action_callees = include_callee && has_action ? Noir::JSCalleeExtractor.callees_for_exported_function(content, path, "action") : nil

      verbs.map do |verb|
        endpoint_line = verb == "GET" ? (loader_line || 1) : (action_line || 1)
        endpoint = file_route_endpoint(url, verb, path, endpoint_line)
        if include_callee
          callees = verb == "GET" ? loader_callees : action_callees
          callees.try &.each do |name, callee_path, callee_line|
            endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
          end
        end
        endpoint
      end
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

    # `[...]` is the only thing that nests in a Remix flat-route filename, and
    # a filename has no string literals, so quote handling is off — a route
    # named `it's.tsx` would otherwise open a quoted run and never split.
    # Empties are kept and parts are not stripped because `normalize_segment`
    # and the caller decide what an empty segment means; a filename cannot
    # contain leading or trailing whitespace worth trimming anyway.
    FLAT_SEGMENT_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Bracket,
      quotes: "",
      escape: Noir::TopLevelSplit::Escape::None,
      strip: false,
      empties: Noir::TopLevelSplit::Empties::Keep,
      per_kind: false,
      clamp: true,
    )

    # Split a dot-flat Remix route name on segment separators, treating a
    # `.` inside an escaped `[...]` group as a literal (e.g.
    # `jokes[.]rss` is ONE segment whose URL is `/jokes.rss`, not two).
    private def split_flat_segments(name : String) : Array(String)
      Noir::TopLevelSplit.split(name, '.', FLAT_SEGMENT_RULES)
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
  end
end
