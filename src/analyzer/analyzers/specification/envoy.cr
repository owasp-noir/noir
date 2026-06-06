require "../../../models/analyzer"

module Analyzer::Specification
  # Extracts HTTP endpoints from Envoy proxy route configuration files
  # (YAML or JSON). Handles three layout variants:
  #   - `route_config.virtual_hosts[]` (Envoy bootstrap / static RouteConfiguration)
  #   - `virtual_hosts[]` at top level (xDS RDS RouteConfiguration)
  #   - `resources[].virtual_hosts[]` (xDS resource array)
  #
  # For each route the analyzer extracts:
  #   - Path from `match.prefix`, `match.path`, or `match.safe_regex.regex`
  #   - HTTP method from `match.headers[]` where `name: ":method"`
  #   - An additional endpoint for `route.prefix_rewrite` when it differs
  #     from the matched path
  class Envoy < Analyzer
    def analyze
      locator = CodeLocator.instance

      yaml_files = locator.all("envoy-yaml")
      if yaml_files.is_a?(Array(String))
        yaml_files.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_yaml(YAML.parse(content), details)
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      json_files = locator.all("envoy-json")
      if json_files.is_a?(Array(String))
        json_files.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          begin
            process_json(JSON.parse(content), details)
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    # ── YAML processing ──────────────────────────────────────────────────────

    private def process_yaml(data : YAML::Any, details : Details)
      extract_virtual_hosts_yaml(data).each do |vh|
        next unless vh.as_h?
        if routes_node = vh["routes"]?
          if routes = routes_node.as_a?
            routes.each { |route| process_route_yaml(route, details) }
          end
        end
      end
    end

    private def extract_virtual_hosts_yaml(data : YAML::Any) : Array(YAML::Any)
      if rc = data["route_config"]?
        if vh = rc["virtual_hosts"]?
          return vh.as_a? || [] of YAML::Any
        end
      end

      if vh = data["virtual_hosts"]?
        return vh.as_a? || [] of YAML::Any
      end

      result = [] of YAML::Any
      if resources = data["resources"]?
        if arr = resources.as_a?
          arr.each do |resource|
            next unless resource.as_h?
            if vh = resource["virtual_hosts"]?
              if vharr = vh.as_a?
                result.concat(vharr)
              end
            end
          end
        end
      end
      result
    end

    private def process_route_yaml(route : YAML::Any, details : Details)
      return unless route.as_h?
      return unless match = route["match"]?

      path = extract_path_yaml(match)
      return if path.nil? || path.empty?

      method = extract_method_yaml(match) || "GET"
      url = build_url(path)
      @result << Endpoint.new(url, method, details)

      if (route_action = route["route"]?) && route_action.as_h?
        if rewrite = route_action["prefix_rewrite"]?.try(&.as_s?)
          rewritten_url = build_url(rewrite)
          @result << Endpoint.new(rewritten_url, method, details) unless rewritten_url == url
        end
      end
    end

    private def extract_path_yaml(match : YAML::Any) : String?
      return unless match.as_h?
      if prefix = match["prefix"]?.try(&.as_s?)
        return prefix
      end
      if path = match["path"]?.try(&.as_s?)
        return path
      end
      if (safe_regex = match["safe_regex"]?) && safe_regex.as_h?
        return safe_regex["regex"]?.try(&.as_s?)
      end
      # Envoy v2 legacy field
      match["regex"]?.try(&.as_s?)
    end

    private def extract_method_yaml(match : YAML::Any) : String?
      return unless match.as_h?
      return unless headers_node = match["headers"]?
      return unless headers = headers_node.as_a?
      headers.each do |header|
        next unless header.as_h?
        next unless header["name"]?.try(&.as_s?) == ":method"
        if exact = header["exact_match"]?.try(&.as_s?)
          return exact.upcase
        end
        if (sm = header["string_match"]?) && sm.as_h?
          if exact2 = sm["exact"]?.try(&.as_s?)
            return exact2.upcase
          end
        end
      end
      nil
    end

    # ── JSON processing ───────────────────────────────────────────────────────

    private def process_json(data : JSON::Any, details : Details)
      extract_virtual_hosts_json(data).each do |vh|
        next unless vh.as_h?
        if routes_node = vh["routes"]?
          if routes = routes_node.as_a?
            routes.each { |route| process_route_json(route, details) }
          end
        end
      end
    end

    private def extract_virtual_hosts_json(data : JSON::Any) : Array(JSON::Any)
      if rc = data["route_config"]?
        if vh = rc["virtual_hosts"]?
          return vh.as_a? || [] of JSON::Any
        end
      end

      if vh = data["virtual_hosts"]?
        return vh.as_a? || [] of JSON::Any
      end

      result = [] of JSON::Any
      if resources = data["resources"]?
        if arr = resources.as_a?
          arr.each do |resource|
            next unless resource.as_h?
            if vh = resource["virtual_hosts"]?
              if vharr = vh.as_a?
                result.concat(vharr)
              end
            end
          end
        end
      end
      result
    end

    private def process_route_json(route : JSON::Any, details : Details)
      return unless route.as_h?
      return unless match = route["match"]?

      path = extract_path_json(match)
      return if path.nil? || path.empty?

      method = extract_method_json(match) || "GET"
      url = build_url(path)
      @result << Endpoint.new(url, method, details)

      if (route_action = route["route"]?) && route_action.as_h?
        if rewrite = route_action["prefix_rewrite"]?.try(&.as_s?)
          rewritten_url = build_url(rewrite)
          @result << Endpoint.new(rewritten_url, method, details) unless rewritten_url == url
        end
      end
    end

    private def extract_path_json(match : JSON::Any) : String?
      return unless match.as_h?
      if prefix = match["prefix"]?.try(&.as_s?)
        return prefix
      end
      if path = match["path"]?.try(&.as_s?)
        return path
      end
      if (safe_regex = match["safe_regex"]?) && safe_regex.as_h?
        return safe_regex["regex"]?.try(&.as_s?)
      end
      match["regex"]?.try(&.as_s?)
    end

    private def extract_method_json(match : JSON::Any) : String?
      return unless match.as_h?
      return unless headers_node = match["headers"]?
      return unless headers = headers_node.as_a?
      headers.each do |header|
        next unless header.as_h?
        next unless header["name"]?.try(&.as_s?) == ":method"
        if exact = header["exact_match"]?.try(&.as_s?)
          return exact.upcase
        end
        if (sm = header["string_match"]?) && sm.as_h?
          if exact2 = sm["exact"]?.try(&.as_s?)
            return exact2.upcase
          end
        end
      end
      nil
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    # Envoy emits path-only URLs. The `virtual_hosts[].domains` value carries
    # host-routing context but is not embedded in the URL because the endpoint
    # optimizer always normalises paths to `/`-prefixed strings.
    private def build_url(path : String) : String
      path
    end
  end
end
