require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./mounted_router_support"
require "../../../detector/detectors/python/chalice"

module Analyzer::Python
  class Chalice < PythonEngine
    include MountedRouterSupport
    analyzer_for "python_chalice"

    # Reference: https://aws.github.io/chalice/topics/routing.html
    #
    # `@app.route(path, methods=[...], authorizer=, api_key_required=)` on a
    # `Chalice(...)` app or a `Blueprint(__name__)`; GET when no methods are
    # given. `app.register_blueprint(bp, url_prefix="/x")` prefixes a
    # blueprint. Request data is read off `app.current_request`. Non-HTTP
    # handlers (`@app.lambda_function`, `@app.schedule`, event sources) are
    # not routes.

    PATH_PARAM_RE = /\{([A-Za-z_]\w*)\}/
    ALIAS_RE      = /\b([A-Za-z_]\w*)\s*=\s*(?:\w+\.)*current_request\b(?!\s*\.)/
    REQUEST_ATTRS = {"query_params" => "query", "json_body" => "json", "headers" => "header"}
    TAGGER        = "chalice_analyzer"

    def analyze
      emit_mounted_routes(ordered_parallel_analyze(python_source_files) do |path|
        scan_file(path, python_base_path_for(path))
      end)
      result
    end

    private def scan_file(path : ::String, base_path : ::String) : FileScan?
      source = read_file_content(path)
      return unless source.includes?("chalice") && source.matches?(Detector::Python::Chalice::IMPORT_RE)

      # `register_blueprint(blueprint, name_prefix=None, url_prefix=None)`
      mounts = collect_mounts(source, path, base_path, "register_blueprint", "blueprint", "url_prefix", 2)

      lines = source.lines
      routes = [] of Route
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source).each do |deco|
        next unless deco.attribute_name == "route"

        body, callees = handler_body(lines, deco.def_line, path, base_path, source)
        params = deco.path.scan(PATH_PARAM_RE).map { |m| Param.new(m[1], "", "path") }
        params.concat(request_params(body, "current_request", ALIAS_RE, REQUEST_ATTRS))

        tags = [] of Tag
        if (authorizer = deco.keywords["authorizer"]?) && authorizer != "None"
          tags << Tag.new("auth", "Protected by Chalice authorizer=#{authorizer}", TAGGER)
        elsif deco.keywords["api_key_required"]? == "True"
          tags << Tag.new("auth", "Protected by Chalice api_key_required=True", TAGGER)
        end

        routes << Route.new(deco.router_name, deco.path, deco.methods.uniq, params, deco.decorator_line + 1, callees, tags)
      end
      FileScan.new(path, routes, mounts) unless routes.empty? && mounts.empty?
    end
  end
end
