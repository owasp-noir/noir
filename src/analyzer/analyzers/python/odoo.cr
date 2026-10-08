require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./python_helper"
require "../../../detector/detectors/python/odoo"

module Analyzer::Python
  class Odoo < PythonEngine
    analyzer_for "python_odoo"

    # Reference: https://www.odoo.com/documentation/master/developer/reference/backend/http.html
    #
    # Controllers are `http.Controller` methods decorated with
    # `@http.route(path_or_paths, type=, auth=, methods=, csrf=)` (or a bare
    # `@route` from `from odoo.http import route`). An override decorated
    # with an empty `@http.route()` re-exposes its parent's route and yields
    # nothing here, so the parent's declaration is the one reported.
    #
    # Handler keyword arguments are the request parameters: query/form for
    # `type="http"`, JSON-RPC `params` for `type="json"`/`"jsonrpc"`.

    PATH_PARAM_RE  = /<(?:[^<>]*:)?([A-Za-z_]\w*)>/
    PROTECTED_AUTH = %w[user bearer]
    TAGGER         = "odoo_analyzer"

    def analyze
      ordered_parallel_analyze(python_source_files) do |path|
        analyze_file(path, python_base_path_for(path))
      end.each { |endpoints| result.concat(endpoints) }
      result
    end

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("route") && source.matches?(Detector::Python::Odoo::IMPORT_RE)

      lines = source.lines
      endpoints = [] of Endpoint
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, ["http"], bare_route: true).each do |deco|
        next unless deco.attribute_name == "route"

        kind = deco.keywords["type"]? || "http"
        json = kind == "json" || kind == "jsonrpc"
        # No literal `methods=` means any method; JSON-RPC is always POSTed.
        declared = deco.keywords["methods"]?.try(&.upcase)
        methods = if declared && deco.methods.all? { |m| declared.includes?(m) }
                    deco.methods
                  else
                    json ? ["POST"] : ["GET", "POST"]
                  end
        auth = deco.keywords["auth"]? || "user"

        def_line = deco.def_line
        body = def_line >= 0 ? extract_function_body(lines, def_line) : ""
        arg_names = def_line >= 0 ? handler_kwarg_names(lines, def_line, body, ["request.params"]) : [] of ::String
        callees = def_line >= 0 ? build_callees_from(body, def_line + 1, path, definition_base_path: base_path, source: source) : [] of Callee

        deco.paths.each do |route|
          path_names = [] of ::String
          url = Helper.normalize_path(route.gsub(PATH_PARAM_RE) { path_names << $~[1]; "{#{$~[1]}}" })

          methods.each do |method|
            param_type = json ? "json" : (method == "GET" || method == "HEAD" ? "query" : "form")
            params = path_names.uniq.map { |name| Param.new(name, "", "path") }
            (arg_names - path_names).each { |name| params << Param.new(name, "", param_type) }

            endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
            endpoint.add_tag(Tag.new("auth", "Protected by Odoo auth='#{auth}'", TAGGER)) if PROTECTED_AUTH.includes?(auth)
            endpoint.add_tag(Tag.new("odoo-auth", auth, TAGGER))
            endpoint.add_tag(Tag.new("odoo-type", kind, TAGGER))
            endpoint.add_tag(Tag.new("csrf-disabled", "Odoo csrf=False", TAGGER)) if deco.keywords["csrf"]? == "False"
            callees.each { |callee| endpoint.push_callee(callee) }
            endpoints << endpoint
          end
        end
      end
      endpoints
    end
  end
end
