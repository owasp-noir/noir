require "../../../models/analyzer"

module Analyzer::Specification
  class K8sGatewayApi < Analyzer
    METHOD_ANY = "ANY"

    def analyze
      spec_files = CodeLocator.instance.all("k8s-gateway-api-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          YAML.parse_all(content).each { |doc| process_doc(doc, details) }
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_doc(doc : YAML::Any, details : Details)
      root = doc.as_h?
      return unless root

      kind = root[YAML::Any.new("kind")]?.try(&.as_s?)
      return unless kind == "HTTPRoute"

      api_version = root[YAML::Any.new("apiVersion")]?.try(&.as_s?)
      return unless api_version && api_version.starts_with?("gateway.networking.k8s.io/")

      spec = root[YAML::Any.new("spec")]?.try(&.as_h?)
      return unless spec

      hosts = collect_hostnames(spec[YAML::Any.new("hostnames")]?)

      rules = spec[YAML::Any.new("rules")]?.try(&.as_a?) || [] of YAML::Any
      rules.each { |rule| process_rule(rule, hosts, details) }
    end

    private def collect_hostnames(node : YAML::Any?) : Array(String)
      result = [] of String
      return result if node.nil?
      arr = node.as_a?
      return result unless arr
      arr.each do |entry|
        if str = entry.as_s?
          result << str unless str.empty?
        end
      end
      result
    end

    private def process_rule(rule : YAML::Any, hosts : Array(String), details : Details)
      rule_h = rule.as_h?
      return unless rule_h

      matches = rule_h[YAML::Any.new("matches")]?.try(&.as_a?) || [] of YAML::Any
      filters = rule_h[YAML::Any.new("filters")]?.try(&.as_a?) || [] of YAML::Any
      url_rewrite = url_rewrite_from(filters)

      matches.each do |match|
        emit_match(match, hosts, url_rewrite, details)
      end
    end

    private def url_rewrite_from(filters : Array(YAML::Any)) : String?
      filters.each do |filter|
        h = filter.as_h?
        next unless h
        type = h[YAML::Any.new("type")]?.try(&.as_s?)
        next unless type == "URLRewrite"
        rewrite = h[YAML::Any.new("urlRewrite")]?.try(&.as_h?)
        next unless rewrite
        path = rewrite[YAML::Any.new("path")]?.try(&.as_h?)
        next unless path
        if value = path[YAML::Any.new("replaceFullPath")]?.try(&.as_s?)
          return value
        end
        if value = path[YAML::Any.new("replacePrefixMatch")]?.try(&.as_s?)
          return value
        end
      end
    end

    private def emit_match(match : YAML::Any, hosts : Array(String), url_rewrite : String?, details : Details)
      match_h = match.as_h?
      return unless match_h

      path_h = match_h[YAML::Any.new("path")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      path_value = path_h[YAML::Any.new("value")]?.try(&.as_s?) || "/"
      path_type = path_h[YAML::Any.new("type")]?.try(&.as_s?) || "PathPrefix"

      method_node = match_h[YAML::Any.new("method")]?
      method = resolve_method(method_node)

      emit_endpoint(path_value, method, path_type, hosts, "match", details)

      if url_rewrite && !url_rewrite.empty? && url_rewrite != path_value
        emit_endpoint(url_rewrite, method, path_type, hosts, "rewrite", details)
      end
    end

    private def resolve_method(node : YAML::Any?) : String
      return METHOD_ANY if node.nil?
      if str = node.as_s?
        return str.empty? ? METHOD_ANY : str.upcase
      end
      if h = node.as_h?
        ["exact", "prefix", "regex"].each do |kind|
          value = h[YAML::Any.new(kind)]?.try(&.as_s?)
          return value.upcase if value && !value.empty?
        end
      end
      METHOD_ANY
    end

    private def emit_endpoint(path : String, method : String, path_type : String, hosts : Array(String), origin : String, details : Details)
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, details)
        endpoint.add_tag(Tag.new("gateway-path-type", path_type.downcase, "k8s_gateway_api_analyzer"))
        endpoint.add_tag(Tag.new("gateway-host", host, "k8s_gateway_api_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("gateway-source", origin, "k8s_gateway_api_analyzer"))
        @result << endpoint
      end
    end
  end
end
