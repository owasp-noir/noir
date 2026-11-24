require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "../../../detector/rule_detector"

module Analyzer::Python
  class Frappe < PythonEngine
    analyzer_for "python_frappe"

    include RuleDetector::SourceCheck

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

    private def analyze_file(path : ::String, base_path : ::String) : Array(Endpoint)?
      source = read_file_content(path)
      return unless source.includes?("whitelist") && source_detector.detect(path, source)

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
        requires = access(guest, guest_unread?(deco.keywords["allow_guest"]?, lines[deco.decorator_line]),
          body, lines[(deco.decorator_line + 1)...def_line])

        methods.each do |method|
          param_type = method == "GET" || method == "HEAD" ? "query" : "form"
          params = arg_names.map { |name| Param.new(name, "", param_type) }
          endpoint = Endpoint.new(url, method, params, Details.new(PathInfo.new(path, deco.decorator_line + 1)))
          if guest
            endpoint.add_tag(Tag.new("frappe-allow-guest", "Frappe allow_guest=True", TAGGER, requires: requires))
          else
            endpoint.add_tag(Tag.new("auth", "Protected by Frappe login (allow_guest=False)", TAGGER, requires: requires))
          end
          endpoint.add_tag(Tag.new("frappe-xss-safe", "Frappe xss_safe=True", TAGGER)) if TRUTHY.includes?(deco.keywords["xss_safe"]?)
          callees.each { |callee| endpoint.push_callee(callee) }
          endpoints << endpoint
        end
      end
      endpoints
    end

    # A role or permission check, or a document write that checks the
    # doctype permission unless told `ignore_permissions=True`.
    BODY_CHECK = /(?m)^.*(?:\bfrappe\.(?:only_for|get_roles)\s*\(|\.(?:has_permission|check_permission)\s*\(|\bfrappe\.session\.user\b|\bPermissionError\b|\.(?:insert|save|submit|delete)\s*\((?![^)]*ignore_permissions\s*=\s*True)).*$/
    BUILTINS   = %w[len str int float bool dict list set tuple isinstance getattr hasattr sorted min max sum range enumerate zip any all abs round print]

    # `allow_guest` written as anything but a literal, or a positional
    # first argument (`whitelist(True)`).
    private def guest_unread?(keyword : ::String?, decorator : ::String) : Bool
      return true if keyword && !TRUTHY.includes?(keyword) && !%w[False 0 None].includes?(keyword)
      decorator.matches?(/whitelist\s*\(\s*(?![A-Za-z_]\w*\s*=)[^\s)]/)
    end

    # `frappe.is_whitelisted` refuses the Guest session a method not
    # whitelisted with `allow_guest=True`. Each check noir does not read is
    # unresolved: another decorator, a role or permission check in the
    # body (read no further than its line), and a call to a helper.
    private def access(guest : Bool, guest_unread : Bool, body : ::String, decorators : Array(::String)) : Array(Access::Clause)
      source = guest ? "Frappe allow_guest=True" : "Frappe login (allow_guest=False)"
      clauses = if guest_unread
                  [Access::Clause.unresolved("#{source}: allow_guest not read", source)]
                else
                  [Access::Clause.new([Access::Atom.new(guest ? Access::Kind::Anonymous : Access::Kind::Authenticated)], source)]
                end
      unread = decorators.map(&.strip).select(&.starts_with?('@'))
      body.scan(BODY_CHECK) { |m| unread << m[0].strip }
      body.scan(/(?<![\w.])([A-Za-z_]\w*)\s*\(/) { |m| unread << "#{m[1]}()" unless BUILTINS.includes?(m[1]) || m[1].in?("def", "if", "elif", "while", "for", "return", "not", "and", "or", "in", "lambda", "print") }
      unread.uniq.each { |fragment| clauses << Access::Clause.unresolved(fragment, fragment) }
      clauses
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
