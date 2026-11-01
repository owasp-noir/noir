require "../../../models/analyzer"
require "../../../miniparsers/csharp_decl_parser"
require "./common"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    analyzer_for "cs_aspnet_mvc"

    include Common

    def analyze
      include_callee = callees_needed?
      # Every project in the scan can carry its own App_Start/RouteConfig.cs.
      CodeLocator.instance.all(Noir::LocatorKeys::CS_APINET_MVC_ROUTECONFIG).uniq.each do |route_config_path|
        analyze_route_config(route_config_path) if File.exists?(route_config_path)
      end

      # Analyze controller files for action methods and parameters
      analyze_controllers(include_callee)

      @result
    end

    private def analyze_route_config(route_config_path : String)
      maproute_check = false
      maproute_buffer = ""
      maproute_line = 0

      # Comments blanked: the stock template trails each argument with one
      # (`name: "Default", // Route name`), which fused into the next item.
      Noir::CSharpLexer.new(read_file_content(route_config_path)).code_source.each_line.with_index do |line, index|
        if line.includes? ".MapRoute("
          maproute_check = true
          maproute_buffer = ""
          maproute_line = index + 1
        end
        next unless maproute_check

        maproute_buffer += line
        next unless line.includes? ");"

        maproute_check = false
        items = maproute_buffer.gsub(/\s+/, "").split(",")
        url = items.find(&.includes?("url:")).try(&.sub("url:", ""))
        # `MapRoute("Default", "{controller}/{action}/{id}", ...)`: the
        # positional form, which the MVC 3 template and older apps use.
        url ||= items[1]? if items[0].ends_with?('"') && items[1]?.try(&.starts_with?('"'))
        if url
          details = Details.new(PathInfo.new(route_config_path, maproute_line))
          @result << Endpoint.new("/#{url.gsub('"', "")}", "GET", details)
        end
      end
    end

    private def analyze_controllers(include_callee : Bool)
      controller_files = get_files_by_extension(".cs").select do |file|
        next false if Common.csharp_test_path?(base_relative_path(file))
        file.includes?("Controller") && !File.basename(file).includes?("RouteConfig")
      end

      core_projects = aspnet_core_project_roots
      bases = local_base_classes
      controller_files.each do |file|
        root = core_projects[:roots].empty? ? nil : Common.project_root_for(file, core_projects[:roots])
        analyze_controller_file(file, bases, !root.nil? && core_projects[:core].includes?(root), include_callee)
      end
    end

    # Project roots (longest first) and the ones that build ASP.NET Core. A
    # Core project's controllers can carry no `Microsoft.AspNetCore` using of
    # their own (`GlobalUsings.cs`, implicit usings), so the project decides.
    # A web SDK project that still references MVC 5 (multi-targeted, or an
    # incremental-migration setup) is not Core-only.
    private def aspnet_core_project_roots : NamedTuple(roots: Array(String), core: Set(String))
      csprojs = get_files_by_extension(".csproj")
      core = Set(String).new
      csprojs.each do |csproj|
        project = read_file_content(csproj)
        core << File.dirname(csproj) if project.matches?(ASPNET_CORE_PROJECT_RE) && !project.matches?(MVC5_REFERENCE_RE)
      rescue
        next
      end
      {roots: Common.project_roots(csprojs), core: core}
    end

    ASPNET_CORE_PROJECT_RE = /Sdk\s*=\s*"Microsoft\.NET\.Sdk\.Web"|FrameworkReference\s+Include\s*=\s*"Microsoft\.AspNetCore\.App"/
    MVC5_REFERENCE_RE      = /System\.Web\.Mvc|Microsoft\.AspNet\.Mvc/
    # Types that exist only in ASP.NET Core.
    ASPNET_CORE_MARKER_RE = /\bIActionResult\b|\[\s*ApiController\b/
    LOCAL_CLASS_BASE_RE   = /\bclass\s+(\w+)(?:\s*<[^<>]*+>)?\s*:\s*([\w.]+)/

    # Every `class Name : Base` in the scan (bases live anywhere, e.g.
    # `Infrastructure/SecureBase.cs`), so a controller's base can be followed
    # to a framework one. A name declared more than once keeps every base.
    #
    # The whole solution is read here, so instead of lexing every file a
    # match is dropped when its own line puts it inside a comment or string.
    # ponytail: line-local check; a declaration-shaped line deep inside a
    # multi-line string or `/* */` body still counts.
    private def local_base_classes : Hash(String, Array(String))
      bases = Hash(String, Array(String)).new
      get_files_by_extension(".cs").each do |file|
        content = read_file_content(file)
        next unless content.matches?(LOCAL_CLASS_BASE_RE)
        prefix = LinePrefixScan.new(content.to_slice)
        content.scan(LOCAL_CLASS_BASE_RE) do |m|
          next unless prefix.code?(m.byte_begin)
          parents = bases[m[1]] ||= [] of String
          parent = m[2].split('.').last
          parents << parent unless parents.includes?(parent)
        end
      rescue
        next
      end
      bases
    end

    # Whether the line text before a byte offset leaves it in code: no `//`,
    # `/*` or `"` earlier on the line, and not a `*`-led `/* */` continuation.
    # Offsets must be asked in increasing order; each byte is read once.
    private class LinePrefixScan
      @position = 0
      @blocked = false
      @line_blank = true

      def initialize(@bytes : Bytes)
      end

      def code?(offset : Int32) : Bool
        while @position < offset
          byte = @bytes[@position]
          if byte == '\n'.ord
            @blocked = false
            @line_blank = true
            @position += 1
            next
          elsif byte == '"'.ord
            @blocked = true
          elsif byte == '/'.ord && (next_byte = @bytes[@position + 1]?) && (next_byte == '/'.ord || next_byte == '*'.ord)
            @blocked = true
          elsif byte == '*'.ord && @line_blank
            @blocked = true
          end
          @line_blank = false unless byte.unsafe_chr.ascii_whitespace?
          @position += 1
        end
        !@blocked
      end
    end

    private def analyze_controller_file(file : String, bases : Hash(String, Array(String)), core_project : Bool,
                                        include_callee : Bool)
      return unless File.exists?(file)

      content = read_file_content(file)
      return unless content.includes?("Controller") && content.includes?("Result")

      # Comment-blanked, so a commented-out attribute or parameter is not read.
      lexer = Noir::CSharpLexer.new(content)
      masked = lexer.masked_source
      # A file that names MVC 5 is classic whatever project it sits in.
      unless masked.includes?("System.Web.Mvc")
        return if core_project || Common.aspnet_core_source?(masked) || masked.matches?(ASPNET_CORE_MARKER_RE)
      end
      web_api_file = !masked.includes?("System.Web.Mvc") && masked.matches?(WEB_API_NAMESPACE_RE)
      lines = lexer.code_lines
      masked_lines = lexer.masked_lines

      Noir::CSharpDeclParser.parse(lexer).types.each do |type|
        # Not routed: `abstract`/`static` classes and open generic ones.
        next unless type.kind == "class" && type.type_params.nil?
        next if type.modifiers.includes?("abstract") || type.modifiers.includes?("static")
        controller_name = controller_class_name(type.name, type.base_name, web_api_file, bases) || next
        controller_prefix = route_prefix(type.attributes)
        type.methods.each do |method|
          next unless method.public? && method.type_params.nil?
          verbs, action_route, explicit, non_action = action_attributes(method.attributes)
          next unless "#{method.return_type} #{method.name}(".matches?(ACTION_RESULT_RE) || explicit
          # `[NonAction]`/`[ChildActionOnly]` and `static` methods, and Web
          # API return types in a file that mixes in Web API controllers.
          next if non_action || method.static? || method.header.matches?(NON_ACTION_SIGNATURE_RE)
          line = method.line + 1
          verbs.each do |http_method, verb_route|
            url = build_url(controller_prefix, verb_route.presence || action_route, controller_name, method.name)
            endpoint = Endpoint.new(url, http_method, Details.new(PathInfo.new(file, line)))
            endpoint.handler = Handler.new(method.name, file, line)
            extract_parameters(method.params, http_method).each { |param| endpoint.params << param }

            # Unlike aspnet_core_mvc, this analyzer parses params from the
            # signature only, so `body_block` exists purely to feed callee
            # extraction — skip building it on the default scan path where
            # `attach_csharp_callees` is a no-op anyway (`include_callee`
            # false).
            if include_callee
              body_block = extract_method_block(lines, masked_lines, method.header_end)
              attach_csharp_callees(endpoint, body_block, file, method.header_end + 1, include_callee, skip_first_line: true)
            end
            @result << endpoint
          end
        end
      end
    end

    VERB_ATTRIBUTES = {"HttpGet" => "GET", "HttpPost" => "POST", "HttpPut" => "PUT", "HttpDelete" => "DELETE", "HttpPatch" => "PATCH"}

    # `{verb, its own route}` per verb attribute (GET when there is none),
    # the `[Route]` template, whether either is present, and `[NonAction]`.
    private def action_attributes(attrs : Array(Noir::CSharpDecl::Attribute)) : Tuple(Array(Tuple(String, String)), String, Bool, Bool)
      verbs = [] of Tuple(String, String)
      route = ""
      explicit = false
      non_action = false
      attrs.each do |attr|
        if verb = VERB_ATTRIBUTES[attr.name]?
          verbs << {verb, attr.positional.first?.try(&.literal) || ""}
          explicit = true
        elsif attr.name == "Route"
          route = attr.positional.first?.try(&.literal) || route
          explicit = true
        elsif attr.name.in?("NonAction", "ChildActionOnly")
          non_action = true
        end
      end
      verbs << {"GET", ""} if verbs.empty?
      {verbs, route, explicit, non_action}
    end

    # `[RoutePrefix("x")]`, else a class-level `[Route("x")]`.
    private def route_prefix(attrs : Array(Noir::CSharpDecl::Attribute)) : String
      template = ->(name : String) { attrs.find(&.name.== name).try(&.positional.first?).try(&.literal).presence }
      template.call("RoutePrefix") || template.call("Route") || ""
    end

    NON_ACTION_SIGNATURE_RE = /\b(?:IHttpActionResult|HttpResponseMessage)\b/

    # The return type ends in `Result` right before the action name:
    # `ActionResult`, `JsonResult`, `FileResult`, `Task<ViewResult>`, ...
    ACTION_RESULT_RE = /Result\s*>?\s+\w+\s*\(/

    WEB_API_NAMESPACE_RE = /\bSystem\.Web\.(?:Http|OData)\b/

    # MVC 5 takes a `*Controller` class whose base is controller-like:
    # `Controller`, a `*Controller`/`*ControllerBase` from a library, or a
    # local class that derives from one. Web API 2 controllers (an
    # `*ApiController`/`ODataController` anywhere up the chain, or a local
    # base in a file that imports Web API but not MVC) route by verb
    # convention, which this analyzer does not model.
    private def controller_class_name(name : String, base : String?, web_api_file : Bool,
                                      bases : Hash(String, Array(String))) : String?
      return unless base && name.ends_with?("Controller") && name != "Controller"
      base_name = base.split('.').last
      return if web_api_file && base_name != "Controller"
      return unless controller_base?(base_name, bases)
      name.rchop("Controller")
    end

    @controller_base_memo = Hash(String, Bool).new

    # Whether `base_name` leads to a framework controller. A name declared
    # more than once counts if any declaration does (`Web/BaseController :
    # Controller` next to `Api/BaseController : ApiController`). Walked with
    # an explicit stack and memoized, so a long or cyclic chain stays linear.
    private def controller_base?(base_name : String, bases : Hash(String, Array(String))) : Bool
      memo = @controller_base_memo
      stack = [base_name]
      expanded = Set(String).new
      while current = stack.last?
        if memo.has_key?(current)
          stack.pop
        elsif current.ends_with?("ApiController") || current == "ODataController"
          memo[current] = false
          stack.pop
        elsif (parents = bases[current]?).nil?
          memo[current] = current.ends_with?("Controller") || current.ends_with?("ControllerBase")
          stack.pop
        elsif expanded.add?(current)
          parents.each { |parent| stack << parent unless memo.has_key?(parent) || expanded.includes?(parent) }
        else
          # Second visit: parents are resolved (a cycle back here reads false).
          memo[current] = parents.any? { |parent| memo[parent]? == true }
          stack.pop
        end
      end
      memo[base_name]
    end

    BINDINGS = {"FromQuery" => "query", "FromRoute" => "path", "FromBody" => "json", "FromHeader" => "header", "FromForm" => "form", "FromCookie" => "cookie"}

    private def extract_parameters(params : Array(Noir::CSharpDecl::Parameter), http_method : String) : Array(Param)
      default_param_type = http_method.in?("POST", "PUT", "PATCH") ? "form" : "query"
      params.compact_map do |param|
        next if param.type.empty?
        next if param.attributes.any?(&.name.in?("FromServices", "FromKeyedServices"))
        bound = param.attributes.compact_map { |attr| BINDINGS[attr.name]? }.first? || default_param_type
        Param.new(param.name, "", bound)
      end
    end

    private def build_url(controller_route : String, action_route : String, controller_name : String, action_name : String) : String
      # `[Route("~/x")]` is app-rooted: it overrides the `[RoutePrefix]`.
      if action_route.starts_with?("~/")
        controller_route = ""
        action_route = action_route.lchop('~')
      end

      parts = [] of String

      # Add controller route if present
      unless controller_route.empty?
        # Replace [controller] placeholder
        route = controller_route.gsub("[controller]", controller_name)
        parts << route unless route.empty?
      end

      # Add action route if present
      if action_route.empty?
        # If no explicit route, use controller and action names
        if controller_route.empty?
          parts << controller_name
        end
        parts << action_name
      else
        parts << action_route
      end

      # Join parts and ensure it starts with /
      url = "/" + parts.join("/").gsub(/\/+/, "/").gsub(/^\//, "")
      url = "/" if url.empty?
      url
    end
  end
end
