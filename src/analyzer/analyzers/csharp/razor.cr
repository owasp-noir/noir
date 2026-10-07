require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  # Razor Pages (`.cshtml`) and Blazor components (`.razor`) declare their
  # routes with an `@page` directive in the markup, not in C# routing code.
  #
  # A Razor page's URL defaults to its path under `Pages/` (`Areas/{area}/Pages/`
  # adds the area), a relative template is appended to that and a `/` or `~/`
  # template replaces it. Verbs come from its `On{Verb}{Handler}[Async]`
  # handlers, in the `.cshtml.cs` page model or an inline `@functions` block.
  # A Blazor component lists absolute templates, one per `@page` or
  # `@attribute [Route]`; it is navigated to with GET and, when it takes
  # `[SupplyParameterFromForm]` values, posted to as a static-SSR form.
  class Razor < Analyzer
    analyzer_for "cs_razor"

    # Line-anchored so a `@@page` CSS rule (Razor's escaped `@`) and prose
    # mentioning `@page` do not count.
    PAGE_DIRECTIVE  = /^[ \t]*@page\b(?:[ \t]+"([^"\n]*)")?/m
    ROUTE_ATTRIBUTE = /^[ \t]*@attribute\s+\[Route\(\s*"([^"\n]*)"/m
    PLACEHOLDER     = /\{([^{}]+)\}/

    # Razor `@* *@`, C# block and line comments. Removed before matching so a
    # commented-out route or handler does not count; newlines are kept so line
    # numbers still line up.
    COMMENT = %r{@\*.*?\*@|/\*.*?\*/|//[^\n]*}m

    # `Task<ActionResult<Dictionary<string, int>>>`, `int[]`, `string?`, `(int, string)`.
    TYPE = %q((?:\([^()]*\)|[\w.]+(?:<[^;{}()=]*>)?)[?\[\]]*)

    # Handlers must be public; the access modifier keeps calls such as
    # `await OnPostAsync()` from reading as declarations.
    HANDLER = /\bpublic\s+(?:(?:async|virtual|override|new)\s+)*#{TYPE}\s+On(Get|Post|Put|Delete|Patch)(\w*)\s*\(((?:[^()]|\([^()]*\))*)\)/

    # The rest of the attribute list, then `public [required ...] Type Name`.
    PROPERTY        = %q(\]\s*(?:\[[^\]]*\]\s*)*public\s+(?:(?:required|virtual|override|new)\s+)*) + TYPE + %q(\s+(\w+))
    BIND_PROPERTY   = /\[BindProperty\b([^\]]*)#{PROPERTY}/
    SUPPLIED        = /\bSupplyParameterFrom(Query|Form)\b(?:\s*\(([^)]*)\))?[^\]]*#{PROPERTY}/
    BIND_PROPERTIES = /\[BindProperties\b/
    # Under a class-level `[BindProperties]`, every public settable property.
    SETTABLE      = /\bpublic\s+(?:(?:required|virtual|override|new)\s+)*#{TYPE}\s+(\w+)\s*\{\s*get;\s*set;/
    NAME_ARGUMENT = /\bName\s*=\s*"([^"]+)"/

    def analyze
      code_files = get_files_by_extension(".cs").to_set

      get_files_by_extensions([".cshtml", ".razor"]).each do |file|
        relative = base_relative_path(file)
        next if Common.csharp_test_path?(relative)

        content = read_file_content(file)
        next unless content.includes?("@page") || content.includes?("@attribute")
        content = strip_comments(content)
        # Code-behind: `Index.cshtml.cs` page model, `Counter.razor.cs` partial.
        code_behind = "#{file}.cs"
        code = code_files.includes?(code_behind) ? "#{content}\n#{strip_comments(read_file_content(code_behind))}" : content

        if file.ends_with?(".razor")
          analyze_component(file, content, code)
        else
          analyze_page(file, relative, content, code)
        end
      end

      @result
    end

    private def strip_comments(source : String) : String
      source.gsub(COMMENT) { |comment| "\n" * comment.count('\n') }
    end

    private def analyze_component(file : String, content : String, code : String)
      query = [] of Param
      form = [] of Param
      code.scan(SUPPLIED) do |m|
        name = m[2]?.try { |args| NAME_ARGUMENT.match(args).try(&.[1]) } || m[3]
        (m[1] == "Query" ? query : form) << Param.new(name, "", m[1].downcase)
      end

      {PAGE_DIRECTIVE, ROUTE_ATTRIBUTE}.each do |directive|
        content.scan(directive) do |m|
          next unless template = m[1]?
          path = url(template)
          line = line_at_byte_offset(content, m.byte_begin)
          endpoint = new_endpoint(path, "GET", file, line)
          query.each { |param| endpoint.push_param(param) }
          @result << endpoint
          next if form.empty?
          endpoint = new_endpoint(path, "POST", file, line)
          form.each { |param| endpoint.push_param(param) }
          @result << endpoint
        end
      end
    end

    private def analyze_page(file : String, relative : String, content : String, code : String)
      # Only the first `@page` counts, and a view without one is a partial or
      # layout, not a routable page.
      return unless m = PAGE_DIRECTIVE.match(content)
      template = m[1]?.presence
      path = if template && template.starts_with?(/~?\//)
               url(template.lchop('~'))
             elsif route = default_route(relative)
               url([route, template].compact.join('/'))
             else
               return
             end
      line = line_at_byte_offset(content, m.byte_begin)

      endpoints = {"GET" => new_endpoint(path, "GET", file, line)}
      code.scan(HANDLER) do |h|
        verb = h[1].upcase
        endpoint = endpoints[verb] ||= new_endpoint(path, verb, file, line)
        handler = h[2].rchop("Async")
        # A named handler is selected with `?handler=Name` unless the template
        # routes it as a `{handler}` segment. One `handler` param per verb:
        # the first name wins.
        if !handler.empty? && !path.includes?("{handler}")
          endpoint.push_param(Param.new("handler", handler, "query"))
        end
        push_handler_params(endpoint, h[3], verb)
      end

      bound = code.scan(BIND_PROPERTY).map { |b| {b[2], b[1].matches?(/SupportsGet\s*=\s*true/)} }
      bound.concat(code.scan(SETTABLE).map { |s| {s[1], false} }) if code.matches?(BIND_PROPERTIES)
      bound.each do |name, supports_get|
        endpoints.each do |verb, endpoint|
          if verb != "GET"
            endpoint.push_param(Param.new(name, "", "form"))
          elsif supports_get
            endpoint.push_param(Param.new(name, "", "query"))
          end
        end
      end

      @result.concat(endpoints.values)
    end

    # `Pages/Users/Edit.cshtml` → `Users/Edit`, `Areas/Admin/Pages/Index.cshtml`
    # → `Admin`. ASP.NET only routes pages under the `Pages` root, so a file
    # outside one gets no default route.
    private def default_route(relative : String) : String?
      segments = relative.rchop(".cshtml").split('/').reject(&.empty?)
      return unless root = segments.index("Pages")
      area = segments[root - 1] if root >= 2 && segments[root - 2] == "Areas"
      segments = [area].compact + segments[(root + 1)..]
      segments.pop if segments.last?.try(&.compare("Index", case_insensitive: true)) == 0
      segments.join('/')
    end

    private def url(template : String) : String
      path = template.gsub(PLACEHOLDER) { "{#{Common.route_placeholder_name($1)}}" }
      "/#{path.strip('/')}"
    end

    # `path` is already normalised by `url`, so its placeholders are bare names.
    private def new_endpoint(path : String, verb : String, file : String, line : Int32) : Endpoint
      endpoint = Endpoint.new(path, verb, Details.new(PathInfo.new(file, line)))
      path.scan(PLACEHOLDER) { |m| endpoint.push_param(Param.new(m[1], "", "path")) }
      endpoint
    end

    private def push_handler_params(endpoint : Endpoint, list : String, verb : String)
      Noir::TopLevelSplit.split(list, ',', Noir::TopLevelSplit::Rules::CSHARP_PARAMS).each do |definition|
        source = Common.binding_attribute_type(definition)
        next if source == "service"
        explicit = Common.explicit_binding_name(definition)
        tokens = definition.gsub(/\[[^\]]*\]/, " ").split('=').first.split
        next unless name = tokens.pop?
        next if tokens.empty? || (source.nil? && Common.csharp_service_type?(tokens.last))
        name = explicit || name
        next if endpoint.params.any? { |p| p.param_type == "path" && p.name.compare(name, case_insensitive: true) == 0 }
        endpoint.push_param(Param.new(name, "", source || (verb == "GET" || verb == "DELETE" ? "query" : "form")))
      end
    end
  end
end
