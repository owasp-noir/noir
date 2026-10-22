require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "../../../detector/detectors/python/frappe"

module Analyzer::Python
  class Frappe < PythonEngine
    analyzer_for "python_frappe"

    # Reference: https://frappeframework.com/docs/user/en/api/rest#remote-method-calls
    #
    # A module-level function decorated with
    # `@frappe.whitelist(allow_guest=, xss_safe=, methods=)` is served at
    # `/api/method/<dotted.module.path>.<function>`; its keyword arguments
    # are the request parameters. Whitelisted `Document` methods (inside a
    # class) are reached through `run_doc_method` instead and are skipped.

    TAGGER = "frappe_analyzer"
    TRUTHY = %w[True 1]
    # `frappe.form_dict.member` — attribute reads of the request dict.
    FORM_DICT_ATTR_RE = /\bfrappe\.(?:local\.)?form_dict\.([A-Za-z_]\w*)\b(?!\s*\()/

    def analyze
      ordered_parallel_analyze(python_source_files) do |path|
        analyze_file(path, python_base_path_for(path))
      end.each { |endpoints| result.concat(endpoints) }
      result
    end

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("whitelist") && source.matches?(Detector::Python::Frappe::IMPORT_RE)

      lines = source.lines
      mod = nil
      endpoints = [] of Endpoint
      Noir::TreeSitterPythonRouteExtractor.extract_decorations(source, ["frappe"], {"whitelist" => "GET"}, pathless: true).each do |deco|
        def_line = deco.def_line
        next if deco.attribute_name != "whitelist" || def_line < 0 || lines[def_line].starts_with?(/\s/)

        mod ||= module_name(path)
        url = "/api/method/#{mod}.#{deco.def_name}"
        # ponytail: no literal `methods=` means GET, POST, PUT, DELETE and
        # QUERY are all accepted; only the two clients use are emitted.
        declared = deco.keywords["methods"]?.try(&.upcase)
        methods = declared && deco.methods.all? { |m| declared.includes?(m) } ? deco.methods : ["GET", "POST"]
        guest = TRUTHY.includes?(deco.keywords["allow_guest"]?)

        body = extract_function_body(lines, def_line)
        arg_names = handler_kwarg_names(lines, def_line, body, ["frappe.form_dict", "frappe.local.form_dict"])
        body.scan(FORM_DICT_ATTR_RE) { |m| arg_names << m[1] unless arg_names.includes?(m[1]) }
        callees = build_callees_from(body, def_line + 1, path, definition_base_path: base_path, source: source)

        methods.each do |method|
          param_type = method == "GET" || method == "HEAD" ? "query" : "form"
          params = arg_names.map { |name| Param.new(name, "", param_type) }
          endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
          if guest
            endpoint.add_tag(Tag.new("frappe-allow-guest", "Frappe allow_guest=True", TAGGER))
          else
            endpoint.add_tag(Tag.new("auth", "Protected by Frappe login (allow_guest=False)", TAGGER))
          end
          endpoint.add_tag(Tag.new("frappe-xss-safe", "Frappe xss_safe=True", TAGGER)) if TRUTHY.includes?(deco.keywords["xss_safe"]?)
          callees.each { |callee| endpoint.push_callee(callee) }
          endpoints << endpoint
        end
      end
      endpoints
    end

    # Dotted module path: the file's stem under every enclosing package
    # (directory with an `__init__.py`), as Frappe resolves `/api/method/`.
    private def module_name(path : ::String) : ::String
      stem = File.basename(path, ".py")
      parts = stem == "__init__" ? [] of ::String : [stem]
      dir = File.dirname(File.expand_path(path))
      while File.exists?(File.join(dir, "__init__.py"))
        parts.unshift(File.basename(dir))
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      parts.join(".")
    end
  end
end
