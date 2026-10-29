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
            action_body(path, controller, action, imports)
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
    ADONIS_ROOT_MARKERS   = ["adonisrc.ts", "adonisrc.js", "package.json"]
    # Comment-stripped controller source, once per file per scan.
    @controller_sources = Hash(String, String).new

    private def controller_imports(content : String) : Hash(String, String)
      imports = Hash(String, String).new
      content.scan(CONTROLLER_IMPORT_RE) { |m| imports[m[1]? || m[3]] = m[2]? || m[4] }
      imports
    end

    # The body of `action` on the controller the route file imports.
    # `#controllers/notes_controller` is `app/controllers/notes_controller`
    # under that file's app (the closest `package.json` / `adonisrc`),
    # so a same-named controller in another app is not the one.
    private def action_body(route_file : String, controller : String, action : String, imports : Hash(String, String)) : String?
      spec = imports[controller]? || controller
      file = controller_file(route_file, spec) || return
      Noir::TreeSitterAdonisJsExtractor.method_body(controller_source(file), action)
    rescue IO::Error
      nil
    end

    private def controller_source(file : String) : String
      @controller_sources[file] ||= Noir::JSRouteExtractor.strip_js_comments(read_file_content(file))
    end

    # Closest Adonis app root above `path`: a directory with `package.json`
    # or `adonisrc`. Stops at the scan base.
    private def adonis_app_root(path : String) : String
      dir = File.dirname(Noir::PathScope.expand(path))
      bases = @base_paths.map { |base| Noir::PathScope.normalize_root(base).rstrip('/') }
      loop do
        return dir if ADONIS_ROOT_MARKERS.any? { |marker| File.exists?(File.join(dir, marker)) }
        break if bases.includes?(dir.rstrip('/'))
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      File.dirname(Noir::PathScope.expand(path))
    end

    # `spec` is an import (`#controllers/notes_controller`, `./notes_controller`,
    # v5 `Admin/NotesController`). The file has to sit at that path under the
    # importing app. A basename match anywhere in the scan is not used.
    private def controller_file(route_file : String, spec : String) : String?
      spec = spec.sub(/\.(?:ts|js)\z/, "")
      if spec.starts_with?('.')
        expanded = File.expand_path(spec, File.dirname(Noir::PathScope.expand(route_file)))
        return scanned_with_extension(expanded)
      end

      root = adonis_app_root(route_file)
      rels = [] of String
      if spec.starts_with?("#controllers/")
        rels << "app/#{spec.lchop('#')}"
      elsif spec.starts_with?('#')
        rels << spec.lchop('#')
      elsif spec.includes?('/')
        rels << File.join("app", "controllers", spec)
        rels << spec
      else
        rels << File.join("app", "controllers", spec)
        snake = spec.gsub(/([a-z0-9])([A-Z])/) { "#{$1}_#{$2}" }.downcase
        rels << File.join("app", "controllers", snake) unless snake == spec.downcase
      end
      rels.uniq.each do |rel|
        if file = exact_under_root(root, rel)
          return file
        end
      end
      nil
    end

    private def scanned_with_extension(absolute_without_ext : String) : String?
      CONTROLLER_EXTENSIONS.each do |ext|
        candidate = absolute_without_ext + ext
        base = File.basename(candidate)
        hit = get_files_by_basename(base).find { |file| Noir::PathScope.expand(file) == Noir::PathScope.expand(candidate) }
        return hit if hit
      end
      nil
    end

    private def exact_under_root(root : String, relative_without_ext : String) : String?
      root_norm = Noir::PathScope.normalize_root(root)
      CONTROLLER_EXTENSIONS.each do |ext|
        want = "#{relative_without_ext}#{ext}"
        get_files_by_relative_path(want, root).each do |file|
          expanded = CodeLocator.instance.expanded_path_for(file)
          next unless Noir::PathScope.under_normalized_root?(expanded, root_norm)
          rel = expanded.byte_slice((root_norm.bytesize + 1)..)
          return file if rel == want
        end
      end
      nil
    end

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
        m[1].split(',').each do |item|
          name = item.split(/[:=]/).first.strip
          next if name.empty? || name.starts_with?("...")
          push.call(name, type)
        end
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
