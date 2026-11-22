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
        custom_parser = nil.as(Bool?)
        Noir::TreeSitterAdonisJsExtractor.extract_routes(content, include_callee, path).each do |route|
          endpoint = build_endpoint(route, path, include_callee)
          params = route.controller.try do |controller, action|
            action_params(path, controller, action, imports)
          end || route.request_params
          params.each do |name, type|
            # request.body() has no fields on GET/HEAD with the default
            # parser. A project-supplied parser can opt those methods in.
            if type == "json" && endpoint.method.in?("GET", "HEAD")
              custom_parser = custom_body_parser?(path) if custom_parser.nil?
              next unless custom_parser
            end
            location = type == "merged" ? (endpoint.method.in?("GET", "HEAD") ? "query" : "json") : type
            endpoint.push_param(Param.new(name, "", location))
          end
          @result << endpoint
        end
      end

      Fiber.yield
      @result
    end

    private def custom_body_parser?(path : String) : Bool
      root = adonis_app_root(path)
      %w[bodyparser bodyParser].any? do |name|
        JS_EXTENSIONS.any? { |ext| CodeLocator.instance.source_path?(File.join(root, "config", name + ext)) }
      end
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
    @controller_methods = Hash(String, Hash(String, Array(Tuple(String, String)))).new
    @controller_files = Hash(Tuple(String, String), String?).new

    private def controller_imports(content : String) : Hash(String, String)
      imports = Hash(String, String).new
      content.scan(CONTROLLER_IMPORT_RE) { |m| imports[m[1]? || m[3]] = m[2]? || m[4] }
      imports
    end

    # Request inputs of `action` on the controller the route file imports.
    # `#controllers/notes_controller` is `app/controllers/notes_controller`
    # under that file's app (the closest `package.json` / `adonisrc`),
    # so a same-named controller in another app is not the one.
    private def action_params(route_file : String, controller : String, action : String, imports : Hash(String, String)) : Array(Tuple(String, String))?
      spec = imports[controller]? || controller
      key = {route_file, spec}
      file = @controller_files.fetch(key) { @controller_files[key] = controller_file(route_file, spec) } || return
      methods = @controller_methods[file] ||= Noir::TreeSitterAdonisJsExtractor.method_params(read_file_content(file), file)
      methods[action]?
    rescue IO::Error
      nil
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

    private def attach_route_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry), path : String)
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path.empty? ? path : callee_path, line: line))
      end
    end
  end
end
