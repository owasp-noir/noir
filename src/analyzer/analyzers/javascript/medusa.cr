require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/js_serverless_function_extractor"

module Analyzer::Javascript
  # Medusa v2 custom APIs are file routes under `src/api`, one exported
  # function per verb (`export const GET`), the same shape as a Next.js
  # App Router `route.ts` with `src/api` in place of `app`.
  #
  #   src/api/store/hello/[id]/route.ts  -> GET /store/hello/{id}
  #   src/api/admin/custom/route.ts      -> POST /admin/custom
  #
  # `[id]` becomes `{id}` via `JavascriptEngine#file_route_url`. Only
  # `route.ts` is a route. Guards live in `middlewares.ts`, not here.
  class Medusa < JavascriptEngine
    analyzer_for "js_medusa"

    PACKAGE_MARKERS = ["\"@medusajs/medusa\"", "\"@medusajs/framework\""]
    API_ROOT        = "/src/api/"

    def analyze
      roots = discover_js_project_roots(PACKAGE_MARKERS, [] of String)
      files = get_files_by_extensions([".ts"]).select { |path| File.basename(path) == "route.ts" }
      ordered_scan_files(files) do |path|
        endpoints_for(path, roots)
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def endpoints_for(path : String, roots : Array(String)) : Array(Endpoint)?
      return unless path_under_project_roots?(path, roots)

      relative = base_relative_path(path)
      return if relative.includes?("/node_modules/")

      segments = api_segments(relative) || return
      content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(path))
      verbs = explicit_api_methods(content)
      return if verbs.empty?

      url = file_route_url(segments)
      verbs.map do |verb|
        handler = Noir::JSServerlessFunctionExtractor.exported_handler(content, verb)
        line = handler.try(&.line) || api_method_line(content, verb) || 1
        endpoint = file_route_endpoint(url, verb, path, line)
        if handler
          Noir::JSServerlessFunctionExtractor.extract_request_params(handler, endpoint, :request)
          validated_body_names(handler).each do |name|
            endpoint.push_param(Param.new(name, "", "json"))
          end
        end
        endpoint
      end
    end

    # Path below `src/api/` with `route.ts` removed, or nil outside it.
    # The prefix before `src/api` is the project location, so a test tree
    # there is not a served API. `src/api/store/test/route.ts` still is.
    private def api_segments(relative : String) : Array(String)?
      idx = relative.index(API_ROOT) || return
      return if in_test_tree?(relative[0...idx])

      rest = relative[(idx + API_ROOT.size)..]
      return unless rest == "route.ts" || rest.ends_with?("/route.ts")

      parts = rest.split('/', remove_empty: true)
      parts.pop
      parts
    end

    # `req.validatedBody.name` is the parsed JSON body. The shared request
    # extractors know `req.body` and do not know this name.
    private def validated_body_names(handler : Noir::JSServerlessFunctionExtractor::Handler) : Array(String)
      body = handler.body
      if name = handler.params.lstrip.match(/\A([A-Za-z_$][\w$]*)/).try(&.[1])
        unless name == "req" || name == "request"
          body = body.gsub(/(?<![\w$.])#{Regex.escape(name)}(?=\s*\??\s*[.\[])/, "req")
        end
      end

      names = [] of String
      body.scan(/(?:req|request)\s*\??\.\s*validatedBody\s*\??\.\s*([A-Za-z_$][\w$]*)\b(?!\s*\()/) do |match|
        names << match[1] unless match[1] == "length"
      end
      body.scan(/(?:req|request)\s*\??\.\s*validatedBody\s*(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        names << match[1]
      end
      body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\s*\??\.\s*validatedBody\b/) do |match|
        match[1].split(',').each do |part|
          clean = part.split(/[:=]/).first.strip.lchop("...")
          names << clean if clean.matches?(/\A[A-Za-z_$][\w$]*\z/)
        end
      end
      names.uniq
    end
  end
end
