require "../../engines/javascript_engine"
require "../../engines/serverless_function_support"

module Analyzer::Javascript
  # Cloudflare Pages Functions: every module under a project's `functions/`
  # directory is a route, its path mirroring the file path.
  #
  #   functions/api/users/[id].ts       -> /api/users/{id}
  #   functions/api/files/[[path]].ts   -> /api/files/{path}   (catch-all)
  #   functions/index.ts                -> /
  #
  # `onRequestGet` / `onRequestPost` / ... exports serve one method each;
  # `onRequest` serves every method without a dedicated export. The
  # `_middleware` modules wrap routes and aren't routes themselves.
  # Rules follow wrangler's `pages functions build` (filepath-routing.ts).
  class CloudflarePages < JavascriptEngine
    include ServerlessFunctionSupport

    analyzer_for "js_cloudflare_pages"

    # The extensions wrangler routes (no `.cjs` / `.mts`).
    EXTENSIONS = [".js", ".mjs", ".ts", ".tsx", ".jsx"]

    VERB_EXPORTS = {
      "onRequestGet"     => "GET",
      "onRequestPost"    => "POST",
      "onRequestPut"     => "PUT",
      "onRequestPatch"   => "PATCH",
      "onRequestDelete"  => "DELETE",
      "onRequestHead"    => "HEAD",
      "onRequestOptions" => "OPTIONS",
    }
    CATCH_ALL_EXPORT = "onRequest"

    def analyze
      include_callee = callees_needed?
      ordered_scan_files(get_files_by_extensions(EXTENSIONS)) do |path|
        segments = route_segments(path) || next
        content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
        next unless content.includes?(CATCH_ALL_EXPORT)
        next if content.includes?("firebase-functions")

        endpoints_for(path, content, file_route_url(segments), include_callee)
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    # File segments below `functions/` with the extension and a trailing
    # `index` dropped, or nil when the file isn't a route module.
    private def route_segments(path : String) : Array(String)?
      return if Noir::ServerlessLayout.non_handler_file?(path)
      _, segments = Noir::ServerlessLayout.routing_remainder(path, base_relative_path(path), "functions") || return
      leaf = Noir::ServerlessLayout.stem(segments.last)
      return if leaf == "_middleware" || leaf == "_middleware_"

      segments = segments[0...-1] + [leaf]
      segments.pop if leaf == "index"
      segments
    end

    private def endpoints_for(path : String, content : String, url : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      VERB_EXPORTS.each do |export_name, verb|
        handler = Noir::JSServerlessFunctionExtractor.exported_handler(content, export_name) || next
        endpoints << serverless_endpoint(url, verb, path, handler, :context, include_callee)
      end
      if handler = Noir::JSServerlessFunctionExtractor.exported_handler(content, CATCH_ALL_EXPORT)
        # `onRequest` alongside verb exports serves only the other methods;
        # ANY covers that, while a body that branches on the method narrows it.
        catch_all_methods(handler).each do |verb|
          next if endpoints.any?(&.method.==(verb))
          endpoints << serverless_endpoint(url, verb, path, handler, :context, include_callee)
        end
      end
      endpoints
    end
  end
end
