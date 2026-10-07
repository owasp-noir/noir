require "../../engines/javascript_engine"

module Analyzer::Javascript
  # Qwik City routes by directory: only `index.*` modules under
  # `src/routes/` become routes, at their directory's path.
  #
  #   src/routes/index.tsx                → GET /
  #   src/routes/about/index.tsx          → GET /about
  #   src/routes/(auth)/login/index.tsx   → GET /login  (group hidden)
  #   src/routes/users/[id]/index.tsx     → GET /users/{id}
  #   src/routes/docs/[...rest]/index.md  → GET /docs/{rest}
  #   src/routes/api/users/index.ts       → its `onGet` / `onPost` / ... exports
  #
  # A default export is the page (GET), an exported `routeAction$` (or
  # modular-forms `formAction$`) posts back to the page (POST), and
  # `onRequest` alone answers every verb.
  # `layout.*`, `plugin.*` and every other module in the tree add no route.
  class QwikCity < JavascriptEngine
    analyzer_for "js_qwik_city"

    EXTENSIONS      = [".tsx", ".jsx", ".ts", ".js", ".md", ".mdx"]
    PACKAGE_MARKERS = ["\"@builder.io/qwik-city\"", "\"@qwik.dev/router\""]
    INDEX_LEAF      = /\Aindex(?:@[\w-]+)?\.\w+\z/
    VERB_EXPORT_RES = FILE_ROUTE_METHODS.to_h do |verb|
      {verb, /export\s+(?:const|let|var|(?:async\s+)?function)\s+on#{verb.capitalize}\b/}
    end
    ON_REQUEST   = /export\s+(?:const|let|var|(?:async\s+)?function)\s+onRequest\b/
    ROUTE_ACTION = /export\s+const\s+\w+\s*=\s*(?:routeAction|formAction)\$\s*\(/

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      # Other `src/routes/` frameworks (SvelteKit, SolidStart) share the
      # layout, so a file counts only when its closest package.json is
      # Qwik City's.
      owners = js_package_owners(PACKAGE_MARKERS)
      return result unless owners.values.includes?(true)

      parallel_file_scan(EXTENSIONS) do |path|
        relative = src_routes_relative(path) || next
        next unless owned_by_js_package?(path, owners)
        segments = relative.split('/')
        next unless segments.pop.matches?(INDEX_LEAF)
        url = file_route_url(segments)

        if path.ends_with?(".md") || path.ends_with?(".mdx")
          mutex.synchronize { result << file_route_endpoint(url, "GET", path) }
          next
        end

        content = begin
          read_file_content(path)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        endpoints = route_endpoints(url, path, content)
        mutex.synchronize { result.concat(endpoints) }
      end

      result
    end

    private def route_endpoints(url : String, path : String, content : String) : Array(Endpoint)
      routes = {} of String => Int32
      VERB_EXPORT_RES.each do |verb, re|
        if match = content.match(re)
          routes[verb] = line_for_match(content, match)
        end
      end
      if match = content.match(DEFAULT_EXPORT_RE)
        routes["GET"] ||= line_for_match(content, match)
      end
      if match = content.match(ROUTE_ACTION)
        routes["POST"] ||= line_for_match(content, match)
      end
      if routes.empty? && (match = content.match(ON_REQUEST))
        fallback_line = line_for_match(content, match)
        FALLBACK_API_METHODS.each { |verb| routes[verb] = fallback_line }
      end

      include_callee = callees_needed?
      routes.map do |verb, line|
        endpoint = file_route_endpoint(url, verb, path, line)
        if include_callee && content.matches?(VERB_EXPORT_RES[verb])
          attach_js_callees(endpoint, Noir::JSCalleeExtractor.callees_for_exported_function(content, path, "on#{verb.capitalize}"))
        end
        endpoint
      end
    end
  end
end
