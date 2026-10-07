require "../../engines/javascript_engine"

module Analyzer::Javascript
  # SolidStart routes every module under `src/routes/` by its file path:
  #
  #   src/routes/index.tsx              → GET /
  #   src/routes/about.tsx              → GET /about
  #   src/routes/blog/(blog).tsx        → GET /blog   (renamed index)
  #   src/routes/(auth)/login.tsx       → GET /login  (group hidden)
  #   src/routes/users/[id].tsx         → GET /users/{id}
  #   src/routes/[...404].tsx           → GET /{404}
  #   src/routes/api/users.ts           → its `GET` / `POST` / ... exports
  #
  # A module's verb exports are API handlers; a default export is the page,
  # served on GET. A module beside a same-named directory (`blog.tsx` next
  # to `blog/`) is that directory's layout and adds no route of its own.
  class Solidstart < JavascriptEngine
    analyzer_for "js_solidstart"

    EXTENSIONS = [".tsx", ".jsx", ".ts", ".js"]
    # `solid-start` is the pre-1.0 package, same layout and verb exports.
    PACKAGE_MARKERS = ["\"@solidjs/start\"", "\"solid-start\""]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      # Other `src/routes/` frameworks (SvelteKit, Qwik City) share the
      # layout, so a file counts only when its closest package.json is
      # SolidStart's.
      owners = js_package_owners(PACKAGE_MARKERS)
      return result unless owners.values.includes?(true)

      parallel_file_scan(EXTENSIONS) do |path|
        relative = src_routes_relative(path) || next
        next unless owned_by_js_package?(path, owners)
        # SolidStart routes every module, so colocated tests would be pages.
        next if relative.includes?(".test.") || relative.includes?(".spec.")

        content = begin
          read_file_content(path)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        verbs = explicit_api_methods(content)
        page = content.match(DEFAULT_EXPORT_RE) unless Dir.exists?(path.rchop(File.extname(path)))
        next if verbs.empty? && page.nil?

        url = url_for(relative)
        endpoints = verbs.map do |verb|
          endpoint = file_route_endpoint(url, verb, path, api_method_line(content, verb) || 1)
          attach_js_callees(endpoint, Noir::JSCalleeExtractor.callees_for_exported_function(content, path, verb)) if include_callee
          endpoint
        end
        if page && !verbs.includes?("GET")
          endpoints << file_route_endpoint(url, "GET", path, line_for_match(content, page))
        end

        mutex.synchronize { result.concat(endpoints) }
      end

      result
    end

    private def url_for(relative : String) : String
      segments = relative.rchop(File.extname(relative)).split('/')
      segments.pop if segments.last == "index"
      file_route_url(segments)
    end
  end
end
