require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "../../../detector/detectors/python/fasthtml"

module Analyzer::Python
  class FastHTML < PythonEngine
    analyzer_for "python_fasthtml"

    # Reference: https://www.fastht.ml/docs/explains/routes.html
    #
    # `@rt(path)` / `@app.route(path)` take the verb from the handler's name
    # (`def post(...)`) and otherwise accept GET and POST. Without a path
    # (`@rt`, `@rt()`) the path is `/<function name>`, `/` for `index`.
    # `@app.get/post/...` work as in Starlette. Handler arguments that are
    # not path params are query (GET/HEAD) or form params; the ones FastHTML
    # injects by name or type (`req`, `session`, `auth`, `htmx`, ...) are not.

    VERBS         = %w[get post put delete patch head options trace]
    INJECTED      = %w[self req request session sess auth htmx app scope]
    PATH_PARAM_RE = /\{([A-Za-z_]\w*)(?::[^}]*)?\}/
    # `app, rt = fast_app()` may name the route decorator something else.
    RT_NAME_RE = /^\s*\w+\s*,\s*(\w+)\s*=\s*fast_app\s*\(/m

    def analyze
      ordered_parallel_analyze(python_source_files) do |path|
        analyze_file(path, python_base_path_for(path))
      end.each { |endpoints| result.concat(endpoints) }
      result
    end

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("fasthtml") && source.matches?(Detector::Python::FastHTML::IMPORT_RE)

      rt_names = ["rt"]
      source.scan(RT_NAME_RE) { |m| rt_names << m[1] }
      lines = source.lines
      endpoints = [] of Endpoint
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, pathless: true, bare_routers: rt_names.uniq).each do |deco|
        def_line = deco.def_line
        next if def_line < 0

        name = deco.def_name
        route = deco.path.empty? ? (name == "index" ? "/" : "/#{name}") : deco.path
        methods = if deco.attribute_name != "route" || deco.keywords.has_key?("methods")
                    deco.methods
                  elsif !deco.path.empty? && VERBS.includes?(name) # path-less `@rt def post()` is GET+POST /post
                    [name.upcase]
                  else
                    ["GET", "POST"]
                  end

        path_names = [] of ::String
        url = route.gsub(PATH_PARAM_RE) { path_names << $~[1]; "{#{$~[1]}}" }
        arg_names = [] of ::String
        parse_function_def(lines, def_line).try &.params.each do |param|
          next if param.name.starts_with?('*') || INJECTED.includes?(param.name) || param.type.includes?("Request")
          arg_names << param.name
        end
        body = extract_function_body(lines, def_line)
        callees = build_callees_from(body, def_line + 1, path, definition_base_path: base_path, source: source)

        methods.each do |method|
          param_type = method == "GET" || method == "HEAD" ? "query" : "form"
          params = path_names.map { |param_name| Param.new(param_name, "", "path") }
          (arg_names - path_names).each { |param_name| params << Param.new(param_name, "", param_type) }
          endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
          callees.each { |callee| endpoint.push_callee(callee) }
          endpoints << endpoint
        end
      end
      endpoints
    end
  end
end
