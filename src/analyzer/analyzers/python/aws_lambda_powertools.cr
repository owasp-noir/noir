require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./mounted_router_support"
require "./python_helper"
require "../../../detector/detectors/python/aws_lambda_powertools"

module Analyzer::Python
  class AwsLambdaPowertools < PythonEngine
    include MountedRouterSupport
    analyzer_for "python_aws_lambda_powertools"

    # Reference: https://docs.powertools.aws.dev/lambda/python/latest/core/event_handler/api_gateway/
    #
    # `@app.get/post/put/patch/delete/head/options(rule)` or
    # `@app.route(rule, method=[...])` on a resolver (`APIGatewayRestResolver`,
    # `ALBResolver`, ...) or a `Router()`; `<name>` segments are path params.
    # `app.include_router(router, prefix="/v1")` prefixes a router. Request
    # data is read off `app.current_event`.

    PATH_PARAM_RE = /<(\w+)>/
    ALIAS_RE      = /\b([A-Za-z_]\w*)\s*=\s*(?:\w+\.)*current_event\b(?!\s*\.)/
    # `current_event.get_query_string_value("q")` / `get_header_value(name="X")`.
    GETTER_RE     = /\.get_(query_string|header)_value\(\s*(?:name\s*=\s*)?['"]([^'"]+)['"]/
    REQUEST_ATTRS = {
      "query_string_parameters"             => "query",
      "multi_value_query_string_parameters" => "query",
      "json_body"                           => "json",
      "headers"                             => "header",
    }
    # `enable_validation=True` handlers take request data as arguments:
    # `Annotated[T, Query()]` / `Header(alias=...)` / `Body()` markers, and
    # plain scalar arguments that are not path params are query params.
    ARG_MARKER_RE = /\b(Query|Header|Cookie|Body|Form|File)\s*\(/
    ARG_MARKERS   = {"Query" => "query", "Header" => "header", "Cookie" => "cookie", "Body" => "json", "Form" => "form", "File" => "form"}
    SCALAR_ARG_RE = /\A(?:Optional\[)?(?:str|int|float|bool)\b/

    def analyze
      emit_mounted_routes(ordered_parallel_analyze(python_source_files) do |path|
        scan_file(path, python_base_path_for(path))
      end)
      result
    end

    private def scan_file(path : ::String, base_path : ::String) : FileScan?
      source = read_file_content(path)
      return unless source.includes?("aws_lambda_powertools") && source.matches?(Detector::Python::AwsLambdaPowertools::IMPORT_RE)

      # `include_router(router, prefix=None)`
      mounts = collect_mounts(source, path, base_path, "include_router", "router", "prefix", 1)

      lines = source.lines
      routes = [] of Route
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source).each do |deco|
        body, callees = handler_body(lines, deco.def_line, path, base_path, source)
        path_names = [] of ::String
        url = deco.path.gsub(PATH_PARAM_RE) { path_names << $~[1]; "{#{$~[1]}}" }
        params = path_names.map { |name| Param.new(name, "", "path") }
        params.concat(argument_params(lines, deco.def_line, path_names))
        params.concat(request_params(body, "current_event", ALIAS_RE, REQUEST_ATTRS))
        body.scan(GETTER_RE) { |m| params << Param.new(m[2], "", m[1] == "header" ? "header" : "query") }

        routes << Route.new(deco.router_name, url, deco.methods.uniq, params, deco.decorator_line + 1, callees)
      end
      FileScan.new(path, routes, mounts) unless routes.empty? && mounts.empty?
    end

    private def argument_params(lines : Array(::String), def_line : Int32, path_names : Array(::String)) : Array(Param)
      params = [] of Param
      return params if def_line < 0
      parse_function_def(lines, def_line).try &.params.each do |arg|
        next if path_names.includes?(arg.name)
        if declaration = {arg.type, arg.default}.find(&.matches?(ARG_MARKER_RE))
          type = ARG_MARKERS[declaration.match!(ARG_MARKER_RE)[1]]
          # Powertools' `Header` converts underscores, like FastAPI's.
          name = Helper.declared_alias(declaration) || (type == "header" ? arg.name.tr("_", "-") : arg.name)
          params << Param.new(name, "", type)
        elsif arg.type.matches?(SCALAR_ARG_RE)
          params << Param.new(arg.name, "", "query")
        end
      end
      params
    end
  end
end
