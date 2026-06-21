require "../../../models/analyzer"

module Analyzer::Specification
  class AwsCloudformation < Analyzer
    METHOD_ANY            = "ANY"
    SAM_FUNCTION_TYPE     = "AWS::Serverless::Function"
    APIGW_RESOURCE_TYPE   = "AWS::ApiGateway::Resource"
    APIGW_METHOD_TYPE     = "AWS::ApiGateway::Method"
    APIGW_RESOURCE_PARENT = "ParentId"

    record ApigwResource, name : String, path_part : String, parent : String?

    def analyze
      spec_files = CodeLocator.instance.all("aws-cloudformation-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          resources = parse_resources(path, content)
          next if resources.empty?

          process_sam(resources, details)
          process_cloudformation(resources, details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private alias ResourceMap = Hash(String, {type: String, properties: Hash(String, JSON::Any)})

    private def parse_resources(path : String, content : String) : ResourceMap
      doc = if path.ends_with?(".json")
              JSON.parse(content)
            else
              JSON.parse(YAML.parse(content).to_json)
            end

      resources = doc["Resources"]?.try(&.as_h?)
      return ResourceMap.new unless resources

      out = ResourceMap.new
      resources.each do |name, node|
        h = node.as_h?
        next unless h
        type = h["Type"]?.try(&.as_s?)
        next unless type
        props = h["Properties"]?.try(&.as_h?) || {} of String => JSON::Any
        out[name] = {type: type, properties: props}
      end
      out
    end

    private def process_sam(resources : ResourceMap, details : Details)
      resources.each do |_, info|
        next unless info[:type] == SAM_FUNCTION_TYPE
        events = info[:properties]["Events"]?.try(&.as_h?)
        next unless events

        events.each_value do |event_node|
          event_h = event_node.as_h?
          next unless event_h
          event_type = event_h["Type"]?.try(&.as_s?) || ""
          next unless event_type == "Api" || event_type == "HttpApi"

          props = event_h["Properties"]?.try(&.as_h?)
          next unless props
          path = props["Path"]?.try(&.as_s?)
          method = props["Method"]?.try(&.as_s?)
          next if path.nil? || path.empty?

          resolved_method = (method.nil? || method.empty?) ? METHOD_ANY : method.upcase
          kind = event_type == "HttpApi" ? "httpapi" : "rest"

          endpoint = Endpoint.new(path, resolved_method, details)
          endpoint.add_tag(Tag.new("sam-event-type", kind, "aws_cloudformation_analyzer"))
          @result << endpoint
        end
      end
    end

    private def process_cloudformation(resources : ResourceMap, details : Details)
      apigw_resources = {} of String => ApigwResource
      methods = [] of NamedTuple(parent_id: String, method: String)

      resources.each do |name, info|
        case info[:type]
        when APIGW_RESOURCE_TYPE
          path_part = info[:properties]["PathPart"]?.try(&.as_s?) || ""
          parent = ref_target(info[:properties][APIGW_RESOURCE_PARENT]?)
          apigw_resources[name] = ApigwResource.new(name, path_part, parent)
        when APIGW_METHOD_TYPE
          http_method = info[:properties]["HttpMethod"]?.try(&.as_s?) || ""
          resource_id = ref_target(info[:properties]["ResourceId"]?) || ""
          next if resource_id.empty?
          methods << {parent_id: resource_id, method: http_method}
        end
      end

      return if methods.empty?

      methods.each do |m|
        path = build_path(m[:parent_id], apigw_resources)
        next if path.empty?

        resolved_method = m[:method].empty? ? METHOD_ANY : m[:method].upcase
        resolved_method = METHOD_ANY if resolved_method == "*"
        endpoint = Endpoint.new(path, resolved_method, details)
        endpoint.add_tag(Tag.new("sam-event-type", "rest", "aws_cloudformation_analyzer"))
        @result << endpoint
      end
    end

    # Resolve `Fn::Ref` / `Fn::GetAtt` / `!Ref` shorthand references that the
    # YAML loader converts into either a tagged string or a `{"Ref": "name"}`
    # object. Returns the referenced resource name, if any.
    private def ref_target(node : JSON::Any?) : String?
      return if node.nil?
      if str = node.as_s?
        return str
      end
      if h = node.as_h?
        if ref = h["Ref"]?.try(&.as_s?)
          return ref
        end
        if get_att = h["Fn::GetAtt"]?
          if arr = get_att.as_a?
            first = arr[0]?.try(&.as_s?)
            return first if first
          elsif str2 = get_att.as_s?
            return str2.split('.').first
          end
        end
        h["Fn::Sub"]?.try(&.as_s?)
      end
    end

    private def build_path(resource_id : String, resources : Hash(String, ApigwResource)) : String
      segments = [] of String
      current = resources[resource_id]?
      visited = Set(String).new
      while current
        break if visited.includes?(current.name)
        visited << current.name
        segments.unshift(current.path_part) unless current.path_part.empty?
        parent_name = current.parent
        break if parent_name.nil?
        current = resources[parent_name]?
      end
      return "" if segments.empty?
      "/" + segments.join('/')
    end
  end
end
