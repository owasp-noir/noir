require "../../engines/specification_engine"

module Analyzer::Specification
  class K8sGatewayApi < SpecificationEngine
    analyzer_for "k8s_gateway_api"

    METHOD_ANY = "ANY"

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::K8S_GATEWAY_API_SPEC) do |path, details|
        content = read_file_content(path)
        YAML.parse_all(content).each { |doc| process_doc(doc, details) }
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

      # `headers` / `queryParams` matchers are request conditions the route
      # will not fire without, so they are attack surface in exactly the way a
      # declared param is — the route is unreachable without sending them.
      params = collect_params(match_h)

      emit_endpoint(path_value, method, path_type, hosts, "match", details, params)

      if url_rewrite && !url_rewrite.empty? && url_rewrite != path_value
        emit_endpoint(url_rewrite, method, path_type, hosts, "rewrite", details, params)
      end
    end

    private def collect_params(match_h : Hash(YAML::Any, YAML::Any)) : Array(Param)
      params = [] of Param
      collect_matcher_params(match_h[YAML::Any.new("headers")]?, "header", params)
      collect_matcher_params(match_h[YAML::Any.new("queryParams")]?, "query", params)
      params
    end

    private def collect_matcher_params(node : YAML::Any?, param_type : String, params : Array(Param))
      return if node.nil?
      return unless arr = node.as_a?

      arr.each do |entry|
        next unless entry_h = entry.as_h?
        name = entry_h[YAML::Any.new("name")]?.try(&.as_s?)
        next if name.nil? || name.empty?
        value = entry_h[YAML::Any.new("value")]?.try(&.as_s?) || ""
        params << Param.new(name, value, param_type)
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

    private def emit_endpoint(path : String, method : String, path_type : String, hosts : Array(String), origin : String, details : Details, params : Array(Param) = [] of Param)
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, params.dup, details)
        endpoint.add_tag(Tag.new("gateway-path-type", path_type.downcase, "k8s_gateway_api_analyzer"))
        endpoint.add_tag(Tag.new("gateway-host", host, "k8s_gateway_api_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("gateway-source", origin, "k8s_gateway_api_analyzer"))
        @result << endpoint
      end
    end
  end
end
