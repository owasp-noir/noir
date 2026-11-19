require "../../engines/specification_engine"

module Analyzer::Specification
  class IstioVirtualservice < SpecificationEngine
    analyzer_for "istio_virtualservice"

    METHOD_ANY = "ANY"

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::ISTIO_VIRTUALSERVICE_SPEC) do |path, details|
        content = read_file_content(path)
        parse_all_yaml_template(content).each { |doc| process_doc(doc, details) }
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

      hosts = string_list(spec[YAML::Any.new("hosts")]?)
      # A route with no `match` (or a match with no `uri`) takes every path.
      # Only reported for a VirtualService bound to an ingress gateway: one
      # bound to `mesh` alone (the default) routes in-cluster traffic.
      catch_all = string_list(spec[YAML::Any.new("gateways")]?).any? { |gateway| gateway != "mesh" }

      http_rules = spec[YAML::Any.new("http")]?.try(&.as_a?) || [] of YAML::Any
      http_rules.each { |rule| process_http_rule(rule, hosts, details, catch_all) }
    end

    private def process_http_rule(rule : YAML::Any, hosts : Array(String), details : Details, catch_all : Bool)
      rule_h = rule.as_h?
      return unless rule_h

      matches = rule_h[YAML::Any.new("match")]?.try(&.as_a?) || [] of YAML::Any
      matches = [YAML::Any.new({} of YAML::Any => YAML::Any)] if catch_all && !rule_h.has_key?(YAML::Any.new("match"))
      rewrite_target = rule_h[YAML::Any.new("rewrite")]?.try(&.as_h?)
        .try(&.[YAML::Any.new("uri")]?)
        .try(&.as_s?)

      matches.each { |match| process_match(match, hosts, rewrite_target, details, catch_all) }
    end

    private def process_match(match : YAML::Any, hosts : Array(String), rewrite_target : String?, details : Details, catch_all : Bool)
      match_h = match.as_h?
      return unless match_h

      uri = match_h[YAML::Any.new("uri")]?
      method_node = match_h[YAML::Any.new("method")]?

      path, path_type = extract_uri_match(uri)
      path = "/" if catch_all && uri.nil?
      return if path.nil? || path.empty?

      method = extract_string_match(method_node) || METHOD_ANY
      method = method.upcase
      # `headers` / `queryParams` matchers: the route does not fire without them.
      params = collect_params(match_h[YAML::Any.new("headers")]?, "header") +
               collect_params(match_h[YAML::Any.new("queryParams")]?, "query")

      emit_endpoint(path, method, path_type, hosts, "match", details, params)

      if rewrite_target && !rewrite_target.empty? && rewrite_target != path
        emit_endpoint(rewrite_target, method, path_type, hosts, "rewrite", details, params)
      end
    end

    # `{x-canary: {exact: "1"}}`: the matcher's string value, or none for a
    # presence-only or regex condition.
    private def collect_params(node : YAML::Any?, param_type : String) : Array(Param)
      params = [] of Param
      node.try(&.as_h?).try &.each do |name, condition|
        value = condition.as_h?.try(&.[YAML::Any.new("exact")]?).try(&.as_s?) || ""
        params << Param.new(name.to_s, value, param_type)
      end
      params
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

    private def emit_endpoint(path : String, method : String, path_type : String, hosts : Array(String), origin : String, details : Details, params : Array(Param) = [] of Param)
      regex = path_type == "regex" && origin == "match" && Noir::URLPath.regex_route?(path)
      path = Noir::URLPath.strip_regex_anchors(path) if path_type == "regex"
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, params.dup, details)
        endpoint.kind = "regex" if regex
        endpoint.add_tag(Tag.new("virtualservice-path-type", path_type, "istio_virtualservice_analyzer"))
        endpoint.add_tag(Tag.new("virtualservice-host", host, "istio_virtualservice_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("virtualservice-source", origin, "istio_virtualservice_analyzer"))
        @result << endpoint
      end
    end
  end
end
