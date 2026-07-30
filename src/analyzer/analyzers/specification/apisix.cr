require "../../engines/specification_engine"

module Analyzer::Specification
  class Apisix < SpecificationEngine
    analyzer_for "apisix"

    def analyze
      each_spec_file("apisix-json") do |path|
        process_json(path)
      end

      each_spec_file("apisix-yaml") do |path|
        process_yaml(path)
      end

      @result
    end

    private def process_json(path : String)
      return unless File.exists?(path)
      details = Details.new(PathInfo.new(path))
      content = read_file_content(path)
      begin
        data = JSON.parse(content)
        routes = data["routes"]?.try(&.as_a?)
        return unless routes
        routes.each { |route| process_route_json(route, details) }
      rescue e
        @logger.debug "Exception processing APISIX JSON #{path}"
        @logger.debug_sub e
      end
    end

    private def process_yaml(path : String)
      return unless File.exists?(path)
      details = Details.new(PathInfo.new(path))
      content = read_file_content(path)
      begin
        data = YAML.parse(content)
        routes = data["routes"]?.try(&.as_a?)
        return unless routes
        routes.each { |route| process_route_yaml(route, details) }
      rescue e
        @logger.debug "Exception processing APISIX YAML #{path}"
        @logger.debug_sub e
      end
    end

    private def process_route_json(route : JSON::Any, details : Details)
      # Skip non-object array entries; subscripting a scalar raises "Expected Hash".
      return unless route.as_h?
      paths = route_paths_json(route)
      return if paths.empty?
      methods = route_methods_json(route)
      hosts = route_hosts_json(route)

      paths.each do |path|
        methods.each do |method|
          @result << build_endpoint(path, method, hosts, details)
        end
      end
    end

    private def process_route_yaml(route : YAML::Any, details : Details)
      # Skip non-object array entries; subscripting a scalar raises "Expected Hash".
      return unless route.as_h?
      paths = route_paths_yaml(route)
      return if paths.empty?
      methods = route_methods_yaml(route)
      hosts = route_hosts_yaml(route)

      paths.each do |path|
        methods.each do |method|
          @result << build_endpoint(path, method, hosts, details)
        end
      end
    end

    private def route_paths_json(route : JSON::Any) : Array(String)
      paths = [] of String
      if uri = route["uri"]?.try(&.as_s?)
        normalized = normalize_path(uri)
        paths << normalized unless normalized.empty?
      end
      if uris = route["uris"]?.try(&.as_a?)
        uris.each do |uri_node|
          if uri_text = uri_node.as_s?
            normalized = normalize_path(uri_text)
            paths << normalized unless normalized.empty?
          end
        end
      end
      paths.uniq
    end

    private def route_paths_yaml(route : YAML::Any) : Array(String)
      paths = [] of String
      if uri = route["uri"]?.try(&.as_s?)
        normalized = normalize_path(uri)
        paths << normalized unless normalized.empty?
      end
      if uris = route["uris"]?.try(&.as_a?)
        uris.each do |uri_node|
          if uri_text = uri_node.as_s?
            normalized = normalize_path(uri_text)
            paths << normalized unless normalized.empty?
          end
        end
      end
      paths.uniq
    end

    private def route_methods_json(route : JSON::Any) : Array(String)
      methods = [] of String
      if method_list = route["methods"]?.try(&.as_a?)
        method_list.each do |method|
          next unless method_text = method.as_s?
          upper = method_text.upcase
          next if upper.empty?
          methods << upper
        end
      end
      normalize_methods(methods)
    end

    private def route_methods_yaml(route : YAML::Any) : Array(String)
      methods = [] of String
      if method_list = route["methods"]?.try(&.as_a?)
        method_list.each do |method|
          next unless method_text = method.as_s?
          upper = method_text.upcase
          next if upper.empty?
          methods << upper
        end
      end
      normalize_methods(methods)
    end

    # A request carries exactly one `Host` header, so a route configured with
    # several (`hosts: [a, b]`) gets one `Host` param — the first, mirroring
    # the single-representative-server rule the OAS analyzers already apply to
    # a multi-entry `servers` block. Emitting one param per host produced
    # `curl -i -X DELETE /internal -H 'Host: a' -H 'Host: b'`, a request no
    # server can answer, and left a duplicate (name, param_type) entry in the
    # inventory that every consumer collapses anyway.
    #
    # The alternates are real attack surface, so they are kept as an
    # `apisix-host` tag instead of being dropped — same shape as iris's
    # `subdomain` and wrangler's `wrangler-zone` tags.
    private def build_endpoint(path : String, method : String, hosts : Array(String), details : Details) : Endpoint
      endpoint = Endpoint.new(path, method, details)
      if primary = hosts.first?
        endpoint.params << Param.new("Host", primary, "header")
        alternates = hosts[1..]
        endpoint.add_tag(Tag.new("apisix-host", alternates.join(", "), "apisix_analyzer")) unless alternates.empty?
      end
      endpoint
    end

    private def route_hosts_json(route : JSON::Any) : Array(String)
      hosts = [] of String
      if host = route["host"]?.try(&.as_s?)
        hosts << host unless host.empty?
      end
      if host_list = route["hosts"]?.try(&.as_a?)
        host_list.each do |host_node|
          next unless host_text = host_node.as_s?
          hosts << host_text unless host_text.empty?
        end
      end
      hosts.uniq
    end

    private def route_hosts_yaml(route : YAML::Any) : Array(String)
      hosts = [] of String
      if host = route["host"]?.try(&.as_s?)
        hosts << host unless host.empty?
      end
      if host_list = route["hosts"]?.try(&.as_a?)
        host_list.each do |host_node|
          next unless host_text = host_node.as_s?
          hosts << host_text unless host_text.empty?
        end
      end
      hosts.uniq
    end

    private def normalize_methods(methods : Array(String)) : Array(String)
      return ["ANY"] if methods.empty?
      return ["ANY"] if methods.includes?("*")
      methods.uniq
    end

    private def normalize_path(path : String) : String
      stripped = path.strip
      return "" if stripped.empty?
      return stripped if stripped.starts_with?("/")
      "/" + stripped
    end
  end
end
