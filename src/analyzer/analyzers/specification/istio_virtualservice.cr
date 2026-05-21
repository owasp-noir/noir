require "../../../models/analyzer"

module Analyzer::Specification
  class IstioVirtualservice < Analyzer
    METHOD_ANY = "ANY"

    def analyze
      spec_files = CodeLocator.instance.all("istio-virtualservice-spec")
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
      return unless kind == "VirtualService"

      api_version = root[YAML::Any.new("apiVersion")]?.try(&.as_s?)
      return unless api_version && api_version.starts_with?("networking.istio.io/")

      spec = root[YAML::Any.new("spec")]?.try(&.as_h?)
      return unless spec

      hosts = collect_string_array(spec[YAML::Any.new("hosts")]?)

      http_rules = spec[YAML::Any.new("http")]?.try(&.as_a?) || [] of YAML::Any
      http_rules.each { |rule| process_http_rule(rule, hosts, details) }
    end

    private def collect_string_array(node : YAML::Any?) : Array(String)
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

    private def process_http_rule(rule : YAML::Any, hosts : Array(String), details : Details)
      rule_h = rule.as_h?
      return unless rule_h

      matches = rule_h[YAML::Any.new("match")]?.try(&.as_a?) || [] of YAML::Any
      rewrite_target = rule_h[YAML::Any.new("rewrite")]?.try(&.as_h?)
        .try(&.[YAML::Any.new("uri")]?)
        .try(&.as_s?)

      matches.each { |match| process_match(match, hosts, rewrite_target, details) }
    end

    private def process_match(match : YAML::Any, hosts : Array(String), rewrite_target : String?, details : Details)
      match_h = match.as_h?
      return unless match_h

      uri = match_h[YAML::Any.new("uri")]?
      method_node = match_h[YAML::Any.new("method")]?

      path, path_type = extract_uri_match(uri)
      return if path.nil? || path.empty?

      method = extract_string_match(method_node) || METHOD_ANY
      method = method.upcase

      emit_endpoint(path, method, path_type, hosts, "match", details)

      if rewrite_target && !rewrite_target.empty? && rewrite_target != path
        emit_endpoint(rewrite_target, method, path_type, hosts, "rewrite", details)
      end
    end

    private def extract_uri_match(node : YAML::Any?) : Tuple(String?, String)
      return {nil, "prefix"} if node.nil?
      h = node.as_h?
      return {nil, "prefix"} unless h
      {"exact", "prefix", "regex"}.each do |kind|
        value = h[YAML::Any.new(kind)]?.try(&.as_s?)
        return {value, kind} if value && !value.empty?
      end
      {nil, "prefix"}
    end

    private def extract_string_match(node : YAML::Any?) : String?
      return if node.nil?
      if str = node.as_s?
        return str.empty? ? nil : str
      end
      h = node.as_h?
      return unless h
      {"exact", "prefix", "regex"}.each do |kind|
        value = h[YAML::Any.new(kind)]?.try(&.as_s?)
        return value if value && !value.empty?
      end
    end

    private def emit_endpoint(path : String, method : String, path_type : String, hosts : Array(String), origin : String, details : Details)
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, details)
        endpoint.add_tag(Tag.new("virtualservice-path-type", path_type, "istio_virtualservice_analyzer"))
        endpoint.add_tag(Tag.new("virtualservice-host", host, "istio_virtualservice_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("virtualservice-source", origin, "istio_virtualservice_analyzer"))
        @result << endpoint
      end
    end
  end
end
