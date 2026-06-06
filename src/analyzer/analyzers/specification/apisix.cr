require "../../../models/analyzer"

module Analyzer::Specification
  class Apisix < Analyzer
    def analyze
      locator = CodeLocator.instance

      json_files = locator.all("apisix-json")
      if json_files.is_a?(Array(String))
        json_files.each { |path| process_json(path) }
      end

      yaml_files = locator.all("apisix-yaml")
      if yaml_files.is_a?(Array(String))
        yaml_files.each { |path| process_yaml(path) }
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
      host_params = host_params_json(route)

      paths.each do |path|
        methods.each do |method|
          endpoint_params = host_params.dup
          @result << Endpoint.new(path, method, endpoint_params, details)
        end
      end
    end

    private def process_route_yaml(route : YAML::Any, details : Details)
      # Skip non-object array entries; subscripting a scalar raises "Expected Hash".
      return unless route.as_h?
      paths = route_paths_yaml(route)
      return if paths.empty?
      methods = route_methods_yaml(route)
      host_params = host_params_yaml(route)

      paths.each do |path|
        methods.each do |method|
          endpoint_params = host_params.dup
          @result << Endpoint.new(path, method, endpoint_params, details)
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

    private def host_params_json(route : JSON::Any) : Array(Param)
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
      hosts.uniq.map { |host_value| Param.new("Host", host_value, "header") }
    end

    private def host_params_yaml(route : YAML::Any) : Array(Param)
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
      hosts.uniq.map { |host_value| Param.new("Host", host_value, "header") }
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
