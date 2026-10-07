require "../../../models/analyzer"
require "../csharp/common"

module Analyzer::VB
  # VB.NET controllers for ASP.NET MVC 5, Web API 2 and ASP.NET Core. The
  # routing model is the C# one; only the syntax differs — `<HttpGet>` for
  # `[HttpGet]`, `Inherits ApiController` for `: ApiController`,
  # `Function X(id As Integer)` for `X(int id)`, case-insensitive keywords.
  #
  # Actions without an attribute route are expanded through the project's
  # conventional route table (`MapHttpRoute` for Web API 2, `MapRoute` /
  # `MapControllerRoute` for MVC), falling back to the framework defaults.
  class AspNetMvc < Analyzer
    analyzer_for "vb_aspnet_mvc"

    include CSharp::Common

    CONTROLLER_RE  = /\bInherits\s+[\w.]*Controller(?:Base)?\b/i
    CLASS_RE       = /\A(?:(?:Public|Friend|Private|Protected|Partial|MustInherit|NotInheritable)\s+)*Class\s+(\w+)/i
    INHERITS_RE    = /\bInherits\s+([\w.]+)/i
    END_CLASS_RE   = /\AEnd\s+Class\b/i
    METHOD_RE      = /\A((?:(?:Public|Private|Protected|Friend|Shared|Overridable|Overrides|NotOverridable|Overloads|Shadows|Async|Iterator)\s+)*)(?:Function|Sub)\s+(\w+)/i
    NON_PUBLIC_RE  = /\b(?:Private|Protected|Friend|Shared|Overrides)\b/i
    LEADING_ATTR   = /\A<((?:[^<>"]|"[^"]*")*)>\s*/
    MAP_ROUTE_RE   = /\.Map(Http|Controller)?Route\s*\(/i
    NAMED_ROUTE_RE = /\b(?:url|routeTemplate|pattern)\s*:=\s*"([^"]*)"/i
    STRING_RE      = /"((?:[^"]|"")*)"/
    PLACEHOLDER_RE = /\{([^{}]+)\}/
    HTTP_ATTR_RE   = /\bHttp(Get|Post|Put|Delete|Patch|Head|Options)(?:Attribute)?\b(?:\s*\(\s*"([^"]*)")?/i
    ROUTE_ATTR_RE  = /\bRoute(?:Prefix)?(?:Attribute)?\s*\(\s*"([^"]*)"/i
    ACTION_NAME_RE = /\bActionName\s*\(\s*"([^"]+)"/i
    ACCEPT_VERBS   = /\bAcceptVerbs\s*\(([^)]*)\)/i
    VERB_WORD_RE   = /\b(Get|Post|Put|Delete|Patch|Head|Options)\b/i
    VERB_PREFIX_RE = /\A(Get|Post|Put|Delete|Patch|Head|Options)/i
    BINDING_RE     = /\bFrom(Body|Uri|Query|Route|Header|Form|Services|KeyedServices)\b/i
    BINDING_NAME   = /\bFrom\w+\s*\(\s*(?:Name\s*:=\s*)?"([^"]+)"/i
    PARAM_MODS     = /\A(?:(?:ByVal|ByRef|Optional|ParamArray)\s+)+/i
    BINDING_TYPES  = {"body" => "json", "uri" => "query", "query" => "query", "route" => "path", "header" => "header", "form" => "form"}

    private record ControllerScope, name : String, attrs : String, webapi : Bool

    def analyze
      sources = ordered_scan_files(get_files_by_extension(".vb").sort) do |file|
        content = read_file_content(file)
        {file, statements(content)} if content.matches?(CONTROLLER_RE) || content.matches?(MAP_ROUTE_RE)
      end

      # ponytail: one route table for the whole scan, first file by path
      # wins; Area registrations (`Admin/{controller}/...`) are left out so
      # they cannot take over the root controllers. Per-project and per-area
      # tables if VB solutions with differing conventions show up.
      api_template = mvc_template = nil
      sources.each do |file, stmts|
        stmts.each do |text, line|
          next unless m = MAP_ROUTE_RE.match(text)
          template = NAMED_ROUTE_RE.match(text[m.end..]).try(&.[1]) ||
                     extract_balanced_param_list(text[m.begin..]).try { |list| split_csharp_parameters(list)[1]? }.try { |arg| STRING_RE.match(arg).try(&.[1]) if arg.starts_with?('"') }
          next unless template
          tokens = template.downcase
          if tokens.includes?("{controller")
            if m[1]?.try(&.downcase) == "http"
              api_template ||= template
            elsif tokens.includes?("{action") && !base_relative_path(file).matches?(/(?:\A|\/)Areas\//i)
              mvc_template ||= template
            end
          else
            emit(file, line, "GET", render(template, "", "", nil), [] of {String, String?})
          end
        end
      end

      sources.each do |file, stmts|
        analyze_controllers(file, stmts, api_template || "api/{controller}/{id}", mvc_template || "{controller}/{action}/{id}")
      end

      @result
    end

    protected def scan_accepts?(path : String) : Bool
      !CSharp::Common.csharp_test_path?(base_relative_path(path))
    end

    private def analyze_controllers(file : String, stmts : Array({String, Int32}), api_template : String, mvc_template : String)
      scopes = [] of ControllerScope?
      pending = [] of String

      stmts.each do |text, line|
        while m = LEADING_ATTR.match(text)
          pending << m[1]
          text = text[m.end..]
        end
        next if text.empty?
        attrs = pending.join(", ")
        pending.clear

        if m = CLASS_RE.match(text)
          name = m[1]
          scopes << (name.downcase.ends_with?("controller") ? classify(name, attrs, text, stmts, line) : nil)
        elsif END_CLASS_RE.matches?(text)
          scopes.pop?
        elsif (scope = scopes.last?) && (m = METHOD_RE.match(text))
          next if m[1].matches?(NON_PUBLIC_RE) || m[2].compare("New", case_insensitive: true) == 0
          next if attrs.matches?(/\bNonAction\b/i)
          action = attrs.match(ACTION_NAME_RE).try(&.[1]) || m[2]
          emit_action(file, line, scope, action, text, attrs, scope.webapi ? api_template : mvc_template)
        end
      end
    end

    # A class is a controller once its base names one. Web API 2 is told
    # apart by its `ApiController` base, since it routes and picks verbs
    # differently from MVC.
    private def classify(name : String, attrs : String, text : String, stmts : Array({String, Int32}), line : Int32) : ControllerScope?
      # `Class X : Inherits Y` on one line; otherwise `Inherits` is the next statement.
      inherits = text.match(INHERITS_RE) || stmts.find { |_, l| l > line }.try { |next_text, _| next_text.match(/\AInherits\s+([\w.]+)/i) }
      base = inherits.try(&.[1]) || ""
      return unless "Inherits #{base}".matches?(CONTROLLER_RE) || attrs.matches?(/\bApiController\b/i)
      ControllerScope.new(name, attrs, base.matches?(/ApiController\z/i))
    end

    private def emit_action(file, line, scope, action, text, attrs, template)
      controller = scope.name.sub(/controller\z/i, "")
      params = parse_params(text)
      prefix = scope.attrs.match(ROUTE_ATTR_RE).try(&.[1])
      # `<RoutePrefix>` (MVC 5 / Web API 2) only prefixes actions that carry
      # their own route; a class-level `<Route>` (Core) routes every action.
      class_routed = scope.attrs.matches?(/\bRoute(?:Attribute)?\s*\(/i)

      verb_routes = [] of {String, String?}
      attrs.scan(HTTP_ATTR_RE) { |m| verb_routes << {m[1].upcase, m[2]?} }
      if av = ACCEPT_VERBS.match(attrs)
        av[1].scan(VERB_WORD_RE) { |m| verb_routes << {m[1].upcase, nil} }
      end
      if verb_routes.empty?
        default = scope.webapi ? (VERB_PREFIX_RE.match(action).try(&.[1].upcase) || "POST") : "GET"
        verb_routes << {default, nil}
      end
      routes = attrs.scan(ROUTE_ATTR_RE).map(&.[1])

      verb_routes.uniq.each do |verb, own|
        (own ? [own] : (routes.empty? ? [nil] : routes)).each do |route|
          url = if route || class_routed
                  route ||= ""
                  path = route.starts_with?('/') || route.starts_with?("~/") ? route : "#{prefix}/#{route}"
                  render(path, controller, action, nil)
                else
                  render(template, controller, action, params.map(&.[0].downcase).to_set)
                end
          emit(file, line, verb, url, params)
        end
      end
    end

    private def emit(file, line, verb, url, params : Array({String, String?}))
      path_params = url.scan(PLACEHOLDER_RE).map(&.[1].downcase).to_set
      endpoint = Endpoint.new(url, verb, Details.new(PathInfo.new(file, line)))
      params.each do |name, binding|
        param_type = binding.try { |b| BINDING_TYPES[b]? } ||
                     (path_params.includes?(name.downcase) ? "path" : ({"POST", "PUT", "PATCH"}.includes?(verb) ? "form" : "query"))
        endpoint.params << Param.new(name, "", param_type)
      end
      path_params.each do |name|
        next if params.any? { |p| p[0].downcase == name }
        endpoint.params << Param.new(name, "", "path")
      end
      @result << endpoint
    end

    # `{name, binding}` per bindable parameter of the signature.
    private def parse_params(signature : String) : Array({String, String?})
      list = extract_balanced_param_list(signature)
      return [] of {String, String?} unless list

      split_csharp_parameters(list).compact_map do |raw|
        binding = BINDING_RE.match(raw).try(&.[1].downcase)
        next if binding.try(&.ends_with?("services"))
        decl = raw.gsub(/<[^>]*>/, "").sub(/=.*\z/m, "").strip.sub(PARAM_MODS, "")
        name, _, type = decl.partition(/\s+As\s+/i)
        next if CSharp::Common.csharp_service_type?(type.strip)
        name = BINDING_NAME.match(raw).try(&.[1]) || name.strip.rchop("()").lchop('[').rchop(']')
        next if name.empty?
        {name, binding}
      end
    end

    # Fills `[controller]`/`[action]` tokens and `{controller}`/`{action}`
    # placeholders, and strips constraints from the rest (`{id:int}` →
    # `{id}`). With `keep`, a segment whose placeholder is not an action
    # parameter is dropped — the optional `{id}` of a conventional route.
    private def render(template : String, controller : String, action : String, keep : Set(String)?) : String
      path = template.lchop('~').gsub(/\[controller\]/i, controller).gsub(/\[action\]/i, action)
      segments = path.split('/').compact_map do |segment|
        kept = true
        segment = segment.gsub(PLACEHOLDER_RE) do |_, m|
          name = CSharp::Common.route_placeholder_name(m[1])
          case name.downcase
          when "controller" then controller
          when "action"     then action
          else
            kept = false if keep && !keep.includes?(name.downcase)
            "{#{name}}"
          end
        end
        segment if kept && !segment.empty?
      end
      "/" + segments.join('/')
    end

    # Comment-stripped logical statements with their 1-based start line. A
    # statement runs on while parens are open (implicit continuation inside
    # an argument list) or the line ends in the explicit ` _`.
    private def statements(content : String) : Array({String, Int32})
      result = [] of {String, Int32}
      buffer = String::Builder.new
      start = 0
      depth = 0
      content.each_line.with_index(1) do |raw, number|
        text, delta = strip_comment(raw)
        start = number if start == 0
        depth = Math.max(0, depth + delta)
        text = text.strip
        explicit = text.ends_with?(" _") || text == "_"
        buffer << (explicit ? text.rchop('_').rstrip : text) << ' '
        next if depth > 0 || explicit
        statement = buffer.to_s.strip
        result << {statement, start} unless statement.empty?
        buffer = String::Builder.new
        start = 0
      end
      statement = buffer.to_s.strip
      result << {statement, start} unless statement.empty?
      result
    end

    # Drops a `'` / `REM` comment and returns the paren delta of the code.
    private def strip_comment(line : String) : {String, Int32}
      return {"", 0} if line.matches?(/\A\s*REM\b/i)
      in_string = false
      depth = 0
      line.each_char_with_index do |char, index|
        if char == '"'
          in_string = !in_string
        elsif !in_string
          case char
          when '\'' then return {line[0, index], depth}
          when '('  then depth += 1
          when ')'  then depth -= 1
          end
        end
      end
      {line, depth}
    end
  end
end
