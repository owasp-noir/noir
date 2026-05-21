require "../../../models/analyzer"

module Analyzer::Specification
  class AwsCdk < Analyzer
    METHOD_ANY = "ANY"

    # Variable -> (parent variable | nil, literal path segment)
    private record Resource, parent : String?, path_part : String

    JS_RESOURCE_RE = /(?:const|let|var)\s+(\w+)\s*(?::\s*[^=]+)?=\s*(\w+(?:\.\w+)*)\.addResource\s*\(\s*(['"`])([^'"`]+)\3/m
    JS_METHOD_RE   = /(\w+)\.addMethod\s*\(\s*(['"`])(\w+)\2/m
    JS_ROUTES_RE   = /(\w+)\.addRoutes\s*\(\s*\{([^}]*)\}/m
    JS_PATH_RE     = /path\s*:\s*(['"`])([^'"`]+)\1/
    JS_METHODS_RE  = /methods\s*:\s*\[([^\]]*)\]/
    JS_METHOD_ITEM = /(?:HttpMethod\.)?([A-Z]+)/

    PY_RESOURCE_RE = /(\w+)\s*=\s*(\w+(?:\.\w+)*)\.add_resource\s*\(\s*(['"])([^'"]+)\3/m
    PY_METHOD_RE   = /(\w+)\.add_method\s*\(\s*(['"])(\w+)\2/m
    PY_ROUTES_RE   = /(\w+)\.add_routes\s*\(([^)]*)\)/m
    PY_PATH_RE     = /path\s*=\s*(['"])([^'"]+)\1/
    PY_METHODS_RE  = /methods\s*=\s*\[([^\]]*)\]/

    def analyze
      spec_files = CodeLocator.instance.all("aws-cdk-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          if path.ends_with?(".py")
            process_python(content, details)
          else
            process_typescript(content, details)
          end
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_typescript(content : String, details : Details)
      resources = collect_resources(content, JS_RESOURCE_RE)
      content.scan(JS_METHOD_RE) do |m|
        var = m[1]
        method = m[3].upcase
        path = resolve_path(var, resources)
        next if path.nil?
        endpoint = Endpoint.new(path, method, details)
        endpoint.add_tag(Tag.new("cdk-event-type", "rest", "aws_cdk_analyzer"))
        @result << endpoint
      end

      content.scan(JS_ROUTES_RE) do |m|
        body = m[2]
        path_match = body.match(JS_PATH_RE)
        next unless path_match
        path = path_match[2]

        methods = extract_js_methods(body)
        methods = [METHOD_ANY] if methods.empty?
        methods.each do |method|
          endpoint = Endpoint.new(path, method, details)
          endpoint.add_tag(Tag.new("cdk-event-type", "httpapi", "aws_cdk_analyzer"))
          @result << endpoint
        end
      end
    end

    private def process_python(content : String, details : Details)
      resources = collect_resources(content, PY_RESOURCE_RE)
      content.scan(PY_METHOD_RE) do |m|
        var = m[1]
        method = m[3].upcase
        path = resolve_path(var, resources)
        next if path.nil?
        endpoint = Endpoint.new(path, method, details)
        endpoint.add_tag(Tag.new("cdk-event-type", "rest", "aws_cdk_analyzer"))
        @result << endpoint
      end

      content.scan(PY_ROUTES_RE) do |m|
        body = m[2]
        path_match = body.match(PY_PATH_RE)
        next unless path_match
        path = path_match[2]

        methods = extract_python_methods(body)
        methods = [METHOD_ANY] if methods.empty?
        methods.each do |method|
          endpoint = Endpoint.new(path, method, details)
          endpoint.add_tag(Tag.new("cdk-event-type", "httpapi", "aws_cdk_analyzer"))
          @result << endpoint
        end
      end
    end

    private def collect_resources(content : String, regex : Regex) : Hash(String, Resource)
      resources = {} of String => Resource
      content.scan(regex) do |m|
        var = m[1]
        parent_expr = m[2]
        path_part = m[4]

        # `<api>.root` (TS/JS) or `<api>.root` (Python) signals the root of
        # an API Gateway tree — treated as having an empty parent chain.
        parent_var = if parent_expr.ends_with?(".root")
                       nil
                     elsif parent_expr.includes?('.')
                       parent_expr.split('.').first
                     else
                       parent_expr
                     end
        resources[var] = Resource.new(parent_var, path_part)
      end
      resources
    end

    private def resolve_path(var : String, resources : Hash(String, Resource)) : String?
      return unless resources.has_key?(var)

      segments = [] of String
      current = var
      visited = Set(String).new
      while res = resources[current]?
        break if visited.includes?(current)
        visited << current
        segments.unshift(res.path_part) unless res.path_part.empty?
        parent = res.parent
        break if parent.nil?
        current = parent
        break unless resources.has_key?(current)
      end

      return if segments.empty?
      "/" + segments.join('/')
    end

    private def extract_js_methods(body : String) : Array(String)
      methods_match = body.match(JS_METHODS_RE)
      return [] of String unless methods_match
      raw = methods_match[1]
      items = [] of String
      raw.scan(JS_METHOD_ITEM) { |m| items << m[1].upcase }
      items
    end

    private def extract_python_methods(body : String) : Array(String)
      methods_match = body.match(PY_METHODS_RE)
      return [] of String unless methods_match
      raw = methods_match[1]
      items = [] of String
      raw.scan(/(?:apigatewayv2\.HttpMethod\.)?([A-Z]+)/) do |m|
        items << m[1].upcase
      end
      items
    end
  end
end
