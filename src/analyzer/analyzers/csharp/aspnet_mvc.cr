require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  class AspNetMvc < Analyzer
    analyzer_for "cs_aspnet_mvc"

    include Common

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The attribute set is fixed, so precompile
    # the route-extraction matchers once at load time.
    ATTRIBUTE_ROUTE_PATTERNS = ["HttpGet", "HttpPost", "HttpPut", "HttpDelete", "HttpPatch", "Route"].to_h do |attribute|
      {attribute, /\b#{attribute}\s*\(\s*"([^"]+)"/}
    end

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
          maproute_buffer = line
          maproute_line = index + 1
        end

        if line.includes? ");"
          maproute_check = false
          unless maproute_buffer.empty?
            buffer = maproute_buffer.gsub(/[\r\n]/, "")
            buffer = buffer.gsub(/\s+/, "")
            buffer.split(",").each do |item|
              if item.includes? "url:"
                url = item.gsub(/url:/, "").gsub(/"/, "")
                details = Details.new(PathInfo.new(route_config_path, maproute_line))
                @result << Endpoint.new("/#{url}", "GET", details)
              end
            end

            maproute_buffer = ""
          end
        end

        if maproute_check
          maproute_buffer += line
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

      i = 0
      http_method = "GET" # Default method for tracking across lines
      action_route = ""   # Track action-level route
      explicit_endpoint_attribute = false
      non_action = false
      # Open class bodies, innermost last: {body depth, controller name or nil
      # for a non-controller class, route prefix}. A file can declare several
      # controllers, and each action belongs to the class it sits in.
      scopes = [] of Tuple(Int32, String?, String)
      pending_class : Tuple(Int32, String?, String)? = nil
      depth = 0

      while i < lines.size
        start_index = i
        line = lines[i]

        # Look for HTTP method attributes (with optional route)
        if line.includes?("[HttpPost")
          http_method = "POST"
          action_route = extract_attribute_route(line, "HttpPost")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpGet")
          http_method = "GET"
          action_route = extract_attribute_route(line, "HttpGet")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpPut")
          http_method = "PUT"
          action_route = extract_attribute_route(line, "HttpPut")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpDelete")
          http_method = "DELETE"
          action_route = extract_attribute_route(line, "HttpDelete")
          explicit_endpoint_attribute = true
        elsif line.includes?("[HttpPatch")
          http_method = "PATCH"
          action_route = extract_attribute_route(line, "HttpPatch")
          explicit_endpoint_attribute = true
        elsif line.includes?("[Route")
          action_route = extract_attribute_route(line, "Route")
          explicit_endpoint_attribute = true
        end
        non_action = true if line.matches?(NON_ACTION_ATTR_RE)

        if class_match = CLASS_DECL_RE.match(masked_lines[i])
          base = class_match[3]? || masked_lines[i + 1]?.try { |next_line| BASE_LIST_LINE_RE.match(next_line).try(&.[1]) }
          before = class_match.pre_match
          body_depth = depth + before.count('{') - before.count('}') + 1
          routable = class_match[2]?.nil? && !before.matches?(NON_ROUTABLE_CLASS_RE)
          name = routable ? controller_class_name(class_match[1], base, web_api_file, bases) : nil
          scope = {body_depth, name, controller_route_prefix(lines, masked_lines, i)}
          # A body opened on the class line can hold an action on that line.
          if class_match.post_match.includes?('{')
            scopes << scope
            pending_class = nil
          else
            pending_class = scope
          end
          # Attributes above the class (`[RoutePrefix]`) are not an action's.
          http_method = "GET"
          action_route = ""
          explicit_endpoint_attribute = false
          non_action = false
        end

        # Check for action method definition
        _, controller_name, controller_prefix = scopes.last? || {0, nil, ""}
        member = line.includes?("(") && (access = MEMBER_ACCESS_RE.match(masked_lines[i]))
        if controller_name && member && access.try(&.[1]) == "public" &&
           (line.matches?(ACTION_RESULT_RE) || explicit_endpoint_attribute)
          signature, end_index = build_signature(lines, masked_lines, i)
          action_name = extract_action_name(signature)
          action_name = "" if non_action || signature.matches?(NON_ACTION_SIGNATURE_RE)
          parameters = extract_parameters(signature, http_method)

          unless action_name.empty?
            # Build URL from controller route, action route, and action name
            url = build_url(controller_prefix, action_route, controller_name, action_name)
            details = Details.new(PathInfo.new(file, i + 1))
            endpoint = Endpoint.new(url, http_method, details)

            parameters.each do |param|
              endpoint.params << param
            end

            # Unlike aspnet_core_mvc, this analyzer parses params from the
            # signature only, so `body_block` exists purely to feed callee
            # extraction — skip building it on the default scan path where
            # `attach_csharp_callees` is a no-op anyway (`include_callee`
            # false).
            if include_callee
              body_block = extract_method_block(lines, masked_lines, end_index)
              attach_csharp_callees(endpoint, body_block, file, end_index + 1, include_callee, skip_first_line: true)
            end
            @result << endpoint
          end
          # Reset to default after processing the method
          http_method = "GET"
          action_route = ""
          explicit_endpoint_attribute = false
          non_action = false
          i = end_index
        elsif member
          # A non-action member ends the attributes that preceded it.
          http_method = "GET"
          action_route = ""
          explicit_endpoint_attribute = false
          non_action = false
        end

        (start_index..i).each do |index|
          depth += masked_lines[index].count('{') - masked_lines[index].count('}')
        end
        if (pending = pending_class) && depth >= pending[0]
          scopes << pending
          pending_class = nil
        end
        while (open = scopes.last?) && depth < open[0]
          scopes.pop
        end

        i += 1
      end
    end

    CLASS_DECL_RE = /\bclass\s+(\w+)(\s*<[^<>]*+>)?\s*(?::\s*([\w.]+))?/
    # Not routed: `abstract`/`static` classes (an open generic one is caught
    # by its `<T>`), `[NonAction]`/`[ChildActionOnly]` and `static` methods,
    # and Web API return types in a file that mixes in Web API controllers.
    MEMBER_ACCESS_RE        = /\b(public|private|protected|internal)\b/
    NON_ROUTABLE_CLASS_RE   = /\b(?:abstract|static)\b/
    NON_ACTION_ATTR_RE      = /[\[,]\s*(?:[\w.]*\.)?(?:NonAction|ChildActionOnly)\b/
    NON_ACTION_SIGNATURE_RE = /\bstatic\b|\b(?:IHttpActionResult|HttpResponseMessage)\b/
    # The return type ends in `Result` right before the action name:
    # `ActionResult`, `JsonResult`, `FileResult`, `Task<ViewResult>`, ...
    ACTION_RESULT_RE = /Result\s*>?\s+\w+\s*\(/
    # A base list wrapped onto the line after the class name.
    BASE_LIST_LINE_RE = /\A\s*:\s*([\w.]+)/

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

    ROUTE_PREFIX_ATTR_RE = /\[\s*RoutePrefix\s*\(\s*"([^"]+)"/
    ROUTE_ATTR_RE        = /\[\s*Route\s*\(\s*"([^"]+)"/

    # `[RoutePrefix("x")]` (else a class-level `[Route("x")]`) on the class
    # line or the attribute lines directly above it.
    private def controller_route_prefix(lines : Array(String), masked_lines : Array(String), index : Int32) : String
      route = nil
      j = index
      while j >= 0 && (j == index || attribute_only_line?(masked_lines[j]))
        if match = ROUTE_PREFIX_ATTR_RE.match(lines[j])
          return match[1]
        end
        route ||= ROUTE_ATTR_RE.match(lines[j]).try(&.[1])
        j -= 1
      end
      route || ""
    end

    private def attribute_only_line?(masked : String) : Bool
      stripped = masked.strip
      stripped.starts_with?('[') && stripped.ends_with?(']')
    end

    private def extract_action_name(line : String) : String
      # Extract method name from: public ActionResult MethodName(params)
      match = line.match(/public\s+(?:async\s+)?(?:override\s+)?(?:virtual\s+)?[\w<>\[\],\s]+\s+(\w+)\s*\(/)
      return "" unless match
      match[1]
    end

    private def extract_parameters(full_signature : String, http_method : String) : Array(Param)
      parameters = [] of Param

      # Extract parameter list (paren-depth aware so a param with an inner ')'
      # — a method-call default like `id = GetDefault()` or a tuple type
      # `(int,int) pair` — isn't truncated at the first ')').
      param_list = extract_balanced_param_list(full_signature)
      return parameters unless param_list

      param_list = param_list.strip
      return parameters if param_list.empty?

      # Determine default parameter type based on HTTP method
      default_param_type = case http_method
                           when "GET"
                             "query"
                           when "POST", "PUT", "PATCH"
                             "form"
                           when "DELETE"
                             "query"
                           else
                             "query"
                           end

      # Parse individual parameters
      split_csharp_parameters(param_list).each do |param_def|
        param_def = param_def.strip
        next if param_def.empty?

        # Check for parameter binding attributes
        param_type = default_param_type
        if param_def.includes?("[FromQuery]")
          param_type = "query"
          param_def = param_def.gsub("[FromQuery]", "").strip
        elsif param_def.includes?("[FromRoute]")
          param_type = "path"
          param_def = param_def.gsub("[FromRoute]", "").strip
        elsif param_def.includes?("[FromBody]")
          param_type = "json"
          param_def = param_def.gsub("[FromBody]", "").strip
        elsif param_def.includes?("[FromHeader]")
          param_type = "header"
          param_def = param_def.gsub("[FromHeader]", "").strip
        elsif param_def.includes?("[FromForm]")
          param_type = "form"
          param_def = param_def.gsub("[FromForm]", "").strip
        elsif param_def.includes?("[FromCookie]")
          param_type = "cookie"
          param_def = param_def.gsub("[FromCookie]", "").strip
        elsif param_def.includes?("[FromServices]") || param_def.includes?("[FromKeyedServices")
          next
        end

        # Extract parameter name (last word before optional default value)
        # Format: "type name" or "type name = default" or "[Attribute] type name"
        parts = param_def.sub(/\s*=.*/m, "").split(/\s+/)
        next if parts.size < 2

        param_name = parts[-1]

        parameters << Param.new(param_name, "", param_type)
      end

      parameters
    end

    private def extract_attribute_route(line : String, attribute : String) : String
      # Extract route from [HttpGet("route")] or [Route("route")]. The
      # attribute's own parens only: in `[HttpPost, ActionName("Delete")]`
      # the literal belongs to ActionName. `[HttpGet, Route("x")]` still
      # routes through its Route.
      attribute_regex = ATTRIBUTE_ROUTE_PATTERNS[attribute]? || /\b#{attribute}\s*\(\s*"([^"]+)"/
      match = line.match(attribute_regex) || line.match(ATTRIBUTE_ROUTE_PATTERNS["Route"])
      return "" unless match
      match[1]
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
