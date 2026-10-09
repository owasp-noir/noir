require "../../engines/javascript_engine"
require "../../engines/serverless_function_support"

module Analyzer::Javascript
  # Vercel Functions: every Node.js module under a project's root `api/`
  # directory is deployed as a function at the matching path.
  #
  #   api/hello.ts          -> /api/hello
  #   api/users/[id].ts     -> /api/users/{id}
  #   api/index.ts          -> /api
  #
  # A default-exported `(req, res)` / `(request)` handler serves every method;
  # `export function GET(request)` style exports serve one each. Entries
  # starting with `_` or `.` are not deployed (`api/_lib/db.ts` is a helper).
  #
  # Only an `api/` at the scan root or directly in a project root counts, and
  # only in a Vercel project (`vercel.json` / `now.json`, an `@vercel/node` /
  # `@vercel/functions` dependency, or a module importing them), so a
  # Next.js `pages/api/` or Nuxt `server/api/` tree never lands here.
  # Rules follow `@vercel/fs-detectors` (detect-builders.ts).
  class VercelFunctions < JavascriptEngine
    include ServerlessFunctionSupport

    analyzer_for "js_vercel_functions"

    # `api/**/*.+(js|mjs|ts|tsx)` — the @vercel/node builder's pattern.
    EXTENSIONS = [".js", ".mjs", ".ts", ".tsx"]

    def analyze
      include_callee = callees_needed?
      vercel_roots = {} of String => Bool
      ordered_scan_files(get_files_by_extensions(EXTENSIONS)) do |path|
        root, segments = route_location(path) || next
        content = read_file_content(path)
        vercel = vercel_roots.fetch(root) { vercel_roots[root] = Noir::ServerlessLayout.vercel_project?(root) }
        next unless vercel || content.matches?(Noir::ServerlessLayout::VERCEL_IMPORT)

        endpoints_for(path, content, file_route_url(["api"] + segments), include_callee)
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    # `{project_root, segments}` for a deployable module under `api/`, with
    # the extension and a trailing `index` dropped from the segments.
    private def route_location(path : String) : Tuple(String, Array(String))?
      return if Noir::ServerlessLayout.non_handler_file?(path)
      root, segments = Noir::ServerlessLayout.routing_remainder(path, base_relative_path(path), "api") || return
      return if Noir::ServerlessLayout.private_segment?(segments)

      leaf = Noir::ServerlessLayout.stem(segments.last)
      segments = segments[0...-1] + [leaf]
      segments.pop if leaf == "index"
      {root, segments}
    end

    private def endpoints_for(path : String, content : String, url : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      FILE_ROUTE_METHODS.each do |verb|
        handler = Noir::JSServerlessFunctionExtractor.exported_handler(content, verb) || next
        endpoints << serverless_endpoint(url, verb, path, handler, :request, include_callee, path_params_in_query: true)
      end
      return endpoints unless endpoints.empty?

      handler = Noir::JSServerlessFunctionExtractor.default_handler(content) || return endpoints
      catch_all_methods(handler).map do |verb|
        serverless_endpoint(url, verb, path, handler, :request, include_callee, path_params_in_query: true)
      end
    end
  end
end
