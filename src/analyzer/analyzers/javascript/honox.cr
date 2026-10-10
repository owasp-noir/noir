require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../utils/url_path"

module Analyzer::Javascript
  # HonoX routes every module under `app/routes/` by its file path:
  #
  #   app/routes/index.tsx            → GET /
  #   app/routes/api/users.ts         → its default export (GET) and
  #                                     `export const POST = createRoute(...)`
  #   app/routes/posts/[id].tsx       → GET /posts/{id}
  #   app/routes/(marketing)/about.tsx → GET /about
  #
  # `_renderer`, `_middleware`, `_error`, `_404` and `$island` modules are
  # not routes. A default-exported `new Hono()` app is mounted at the path.
  class Honox < JavascriptEngine
    analyzer_for "js_honox"

    EXTENSIONS = [".ts", ".tsx", ".js", ".jsx"]
    HONO_APP   = /\bnew\s+Hono\b/

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new
      include_callee = callees_needed?
      owners = js_package_owners(["\"honox\""])
      return result unless owners.values.includes?(true)

      parallel_file_scan(EXTENSIONS) do |path|
        scoped = base_relative_path(path)
        idx = scoped.index("/app/routes/") || next
        relative = scoped[(idx + "/app/routes/".size)..]
        name = File.basename(relative)
        # The same exclusions as HonoX's own `import.meta.glob`.
        next if name.starts_with?('_') || name.starts_with?('$') || name.includes?(".test.") || name.includes?(".spec.")
        next unless owned_by_js_package?(path, owners)

        content = begin
          read_file_content(path)
        rescue e
          logger.debug "Error reading #{path}: #{e.message}"
          next
        end

        segments = relative.rchop(File.extname(relative)).split('/')
        segments.pop if segments.last == "index"
        url = file_route_url(segments)

        endpoints = if content.matches?(HONO_APP)
                      mounted_routes(path, content, url, include_callee)
                    else
                      handler_routes(path, content, url, include_callee)
                    end
        mutex.synchronize { result.concat(endpoints) }
      end

      result
    end

    # `export const POST = createRoute(...)` per verb, `export default` as
    # GET. Each handler runs up to the next export, which bounds the text
    # its `c.req.*` params and callees are read from.
    private def handler_routes(path : String, content : String, url : String, include_callee : Bool) : Array(Endpoint)
      exports = [] of {String, Regex::MatchData}
      FILE_ROUTE_METHODS.each do |verb|
        if match = content.match(EXPORT_CONST_RES[verb]) || content.match(EXPORT_FUNCTION_RES[verb])
          exports << {verb, match}
        end
      end
      if (page = content.match(DEFAULT_EXPORT_RE)) && exports.none? { |verb, _| verb == "GET" }
        exports << {"GET", page}
      end
      exports.sort_by! { |_, match| match.begin(0) }

      exports.map_with_index do |(verb, match), i|
        handler = content[match.end(0)...(exports[i + 1]?.try(&.[1].begin(0)) || content.size)]
        line = line_for_match(content, match)
        endpoint = file_route_endpoint(url, verb, path, line)
        Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
        Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
        Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
        Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
        if include_callee
          callees = Noir::JSCalleeExtractor.callees_for_function_body(handler, path, line, language: javascript_source_language(path))
          attach_js_callees(endpoint, callees.reject { |name, _, _| name == "createRoute" })
        end
        endpoint
      end
    end

    # A Hono sub-app's own routes, prefixed with the module's path.
    private def mounted_routes(path : String, content : String, url : String, include_callee : Bool) : Array(Endpoint)
      Noir::JSRouteExtractor.extract_routes(path, content, @is_debug, include_callees: include_callee).map do |endpoint|
        endpoint.url = endpoint.url == "/" ? url : Noir::URLPath.join(url == "/" ? "" : url, endpoint.url)
        endpoint.url.scan(/\{(\w+)\}|:(\w+)/) { |m| endpoint.push_param(Param.new(m[1]? || m[2], "", "path")) }
        endpoint
      end
    end
  end
end
