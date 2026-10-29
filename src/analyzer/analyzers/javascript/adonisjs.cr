require "../../../models/analyzer"
require "../../../miniparsers/adonisjs_extractor_ts"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Adonisjs < Analyzer
    analyzer_for "js_adonisjs"

    JS_EXTENSIONS = [".js", ".mjs", ".cjs", ".ts"]
    # Precompiled once — a single PCRE2-JIT scan replaces two naive
    # String#includes? substring scans over the whole file content.
    # Regex.union auto-escapes each literal, so it is provably equivalent
    # to the OR-of-includes? it replaces.
    ADONIS_MARKERS_RE = Regex.union("@adonisjs/core", "@ioc:Adonis")

    def analyze
      file_list = all_files()
      file_list.each do |path|
        next unless JS_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
        next unless File.exists?(path)

        content = read_file_content(path)
        next unless content.matches?(ADONIS_MARKERS_RE)
        # Reuse the shared JS test-stub gate so `*.spec.ts` /
        # `*.test.ts` (japa, vitest, jest) AdonisJS test scaffolds
        # don't leak. adonisjs/core's own repo parks ~19 phantom
        # endpoints in `tests/providers.spec.ts` alone.
        next if Noir::JSRouteExtractor.test_stub_only?(path, content)

        include_callee = callees_needed?
        imports = controller_imports(content)
        Noir::TreeSitterAdonisJsExtractor.extract_routes(content, include_callee).each do |route|
          endpoint = build_endpoint(route, path, include_callee)
          handler = route.handler_source || route.controller.try do |controller, action|
            action_body(controller, action, imports)
          end
          handler.try { |body| push_request_params(endpoint, body) }
          @result << endpoint
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterAdonisJsExtractor::Route, path : String, include_callee : Bool) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param

      # Surface AdonisJS's `:slug` placeholders as path Params for
      # parity with how the optimizer expands `{slug}` elsewhere in
      # the codebase.
      route.path.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        params << Param.new(match[1], "", "path")
      end

      endpoint = Endpoint.new(route.path, route.verb, params, details)
      attach_route_callees(endpoint, route.callees, path) if include_callee
      endpoint
    end

    # `const NotesController = () => import('#controllers/notes_controller')`
    # (v6 lazy import) and `import NotesController from '...'`.
    CONTROLLER_IMPORT_RE  = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*\(\s*\)\s*=>\s*import\s*\(\s*['"]([^'"]+)['"]\s*\)|\bimport\s+([A-Za-z_$][\w$]*)\s+from\s+['"]([^'"]+)['"]/
    CONTROLLER_EXTENSIONS = [".ts", ".js"]

    private def controller_imports(content : String) : Hash(String, String)
      imports = Hash(String, String).new
      content.scan(CONTROLLER_IMPORT_RE) { |m| imports[m[1]? || m[3]] = m[2]? || m[4] }
      imports
    end

    # The body of `action` in the controller module `controller` names. The
    # module is found by basename (`#controllers/notes_controller`, v5's
    # `'Admin/NotesController'`), since subpath aliases map onto it.
    # ponytail: basename lookup, first match wins; read package.json
    # `imports` if two controllers ever share a basename.
    private def action_body(controller : String, action : String, imports : Hash(String, String)) : String?
      spec = imports[controller]? || controller
      base = File.basename(spec).sub(/\.(?:ts|js)\z/, "")
      file = CONTROLLER_EXTENSIONS.flat_map { |ext| get_files_by_basename("#{base}#{ext}") }.first? || return
      content = Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
      content.scan(METHOD_DECL_RE) do |m|
        next unless m[1] == action
        open = content.index('(', m.end(0) - 1) || next
        close = Noir::JSLiteralScanner.find_matching_paren(content, open) || next
        brace = content.index('{', close) || next
        stop = Noir::JSLiteralScanner.find_matching_brace(content, brace) || next
        return content[brace..stop]
      end
      nil
    rescue IO::Error
      nil
    end

    METHOD_DECL_RE = /^[ \t]*(?:(?:public|private|protected|static|async)\s+)*([A-Za-z_$][\w$]*)\s*\(/m

    REQUEST_INPUT_RE  = /\brequest\s*\.\s*input\s*\(\s*['"]([^'"]+)['"]/
    REQUEST_ONLY_RE   = /\brequest\s*\.\s*only\s*\(\s*\[([^\]]*)\]/
    REQUEST_QS_RE     = /\brequest\s*\.\s*qs\s*\(\s*\)\s*(?:\.\s*([A-Za-z_$][\w$]*)|\[\s*['"]([^'"]+)['"]\s*\])/
    REQUEST_BODY_RE   = /\brequest\s*\.\s*body\s*\(\s*\)\s*(?:\.\s*([A-Za-z_$][\w$]*)|\[\s*['"]([^'"]+)['"]\s*\])/
    DESTRUCTURED_RE   = /\{([^{}]*)\}\s*=\s*request\s*\.\s*(qs|body|all)\s*\(\s*\)/
    REQUEST_HEADER_RE = /\brequest\s*\.\s*header\s*\(\s*['"]([^'"]+)['"]/
    REQUEST_COOKIE_RE = /\brequest\s*\.\s*(?:plainCookie|encryptedCookie|cookie)\s*\(\s*['"]([^'"]+)['"]/

    # `request.input('x')` / `request.only([...])` read the merged body and
    # query string: the query on a GET, the body otherwise.
    private def push_request_params(endpoint : Endpoint, body : String)
      merged = endpoint.method.in?("GET", "HEAD") ? "query" : "json"
      push = ->(name : String, type : String) { endpoint.push_param(Param.new(name, "", type)) unless name.empty? }
      body.scan(REQUEST_INPUT_RE) { |m| push.call(m[1], merged) }
      body.scan(REQUEST_ONLY_RE) { |m| m[1].scan(/['"]([^'"]+)['"]/) { |n| push.call(n[1], merged) } }
      body.scan(REQUEST_QS_RE) { |m| push.call(m[1]? || m[2], "query") }
      body.scan(REQUEST_BODY_RE) { |m| push.call(m[1]? || m[2], "json") }
      body.scan(DESTRUCTURED_RE) do |m|
        type = m[2] == "qs" ? "query" : (m[2] == "body" ? "json" : merged)
        m[1].split(',').each { |item| push.call(item.split(/[:=]/).first.strip.lchop("..."), type) }
      end
      body.scan(REQUEST_HEADER_RE) { |m| push.call(m[1], "header") }
      body.scan(REQUEST_COOKIE_RE) { |m| push.call(m[1], "cookie") }
    end

    private def attach_route_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry), path : String)
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path.empty? ? path : callee_path, line: line))
      end
    end
  end
end
