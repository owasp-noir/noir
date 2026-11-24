require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./python_helper"
require "../../../detector/rule_detector"

module Analyzer::Python
  class Odoo < PythonEngine
    analyzer_for "python_odoo"

    include RuleDetector::SourceCheck

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

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("route") && source_detector.detect(path, source)

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
        # `auth=public` names a variable, not the literal method.
        literal = !deco.keywords.has_key?("auth") || (deco.def_line >= 0 && lines[deco.decorator_line...deco.def_line].join.matches?(/\bauth\s*=\s*[rRuU]?['"]/))

        def_line = deco.def_line
        body = def_line >= 0 ? extract_function_body(lines, def_line) : ""
        arg_names = def_line >= 0 ? handler_kwarg_names(lines, def_line, body, ["request.params"]) : [] of ::String
        callees = def_line >= 0 ? build_callees_from(body, def_line + 1, path, definition_base_path: base_path, source: source) : [] of Callee

        deco.paths.each do |route|
          url, path_names = Noir::URLPath.rewrite_names(route, PATH_PARAM_RE)
          url = Helper.normalize_path(url)

          methods.each do |method|
            param_type = json ? "json" : (method == "GET" || method == "HEAD" ? "query" : "form")
            params = path_names.uniq.map { |name| Param.new(name, "", "path") }
            (arg_names - path_names).each { |name| params << Param.new(name, "", param_type) }

            endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
            requires = access(auth, literal, body, lines[(deco.decorator_line + 1)...def_line]? || [] of ::String)
            endpoint.add_tag(Tag.new("auth", "Protected by Odoo auth='#{auth}'", TAGGER, requires: requires)) if PROTECTED_AUTH.includes?(auth)
            endpoint.add_tag(Tag.new("odoo-auth", auth, TAGGER, requires: requires))
            endpoint.add_tag(Tag.new("odoo-type", kind, TAGGER))
            endpoint.add_tag(Tag.new("csrf-disabled", "Odoo csrf=False", TAGGER)) if deco.keywords["csrf"]? == "False"
            callees.each { |callee| endpoint.push_callee(callee) }
            endpoints << endpoint
          end
        end
      end
      endpoints
    end

    # `ir.http._auth_method_<auth>`: `user` refuses no uid and the public
    # users; `bearer` takes an API key (scoped by `bearer_scope`) or else
    # falls back to `user`; `public` runs as the public user when nobody is
    # signed in, and `none` runs with no user at all, so both admit anyone.
    # Any other value names a project's own method. Another decorator, and
    # a refusal or group check in the body, are checks noir does not read.
    BODY_CHECK = /(?m)^.*(?:\braise\s+[A-Za-z_]|\.has_group\s*\(|\.check_access\w*\s*\(|\babort\s*\(|\bForbidden\b).*$/

    private def access(auth : ::String, literal : Bool, body : ::String, decorators : Array(::String)) : Array(Access::Clause)
      source = "Odoo auth='#{auth}'"
      clauses = case literal ? auth : nil
                when "user"
                  [Access::Clause.new([Access::Atom.new(:authenticated)], source)]
                when "public", "none"
                  [Access::Clause.new([Access::Atom.new(:anonymous)], source)]
                when "bearer"
                  [Access::Clause.new([Access::Atom.new(:authenticated)], source), Access::Clause.unresolved("bearer_scope", source)]
                else
                  [Access::Clause.unresolved(source, source)]
                end
      unread = decorators.map(&.strip).select(&.starts_with?('@'))
      body.scan(BODY_CHECK) { |m| unread << m[0].strip }
      unread.uniq.each { |fragment| clauses << Access::Clause.unresolved(fragment, fragment) }
      clauses
    end
  end
end
