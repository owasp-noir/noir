require "../../../models/analyzer"

module Analyzer::Specification
  class Kong < Analyzer
    def analyze
      spec_files = CodeLocator.instance.all("kong-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = File.read(path, encoding: "utf-8", invalid: :skip)
        begin
          process_doc(YAML.parse(content), details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_doc(data : YAML::Any, details : Details)
      if data_h = data.as_h?
        process_services(data_h[YAML::Any.new("services")]?, details)
        process_kic(data_h, details)

        if items = data_h[YAML::Any.new("items")]?.try(&.as_a?)
          items.each { |item| process_doc(item, details) }
        end
      elsif data_a = data.as_a?
        data_a.each { |item| process_doc(item, details) }
      end
    end

    private def process_services(services_node : YAML::Any?, details : Details)
      return unless services = services_node.try(&.as_a?)

      services.each do |service|
        next unless service_h = service.as_h?
        upstream = upstream_from(service_h)
        routes = service_h[YAML::Any.new("routes")]?.try(&.as_a?) || [] of YAML::Any
        routes.each { |route| emit_route(route, details, upstream) }
      end
    end

    private def process_kic(data_h : Hash(YAML::Any, YAML::Any), details : Details)
      api_version = data_h[YAML::Any.new("apiVersion")]?.try(&.to_s) || ""
      kind = data_h[YAML::Any.new("kind")]?.try(&.to_s) || ""
      return unless api_version.includes?("configuration.konghq.com/")

      case kind
      when "KongRoute"
        if spec_h = data_h[YAML::Any.new("spec")]?.try(&.as_h?)
          emit_route_hash(spec_h, details, upstream_from(spec_h))
        end
      when "KongIngress"
        if spec_h = data_h[YAML::Any.new("spec")]?.try(&.as_h?)
          if route = spec_h[YAML::Any.new("route")]?
            emit_route(route, details, upstream_from(spec_h))
          end
        end
      end
    end

    private def emit_route(route_node : YAML::Any, details : Details, upstream : String)
      route_h = route_node.as_h?
      return unless route_h

      emit_route_hash(route_h, details, upstream)
    end

    private def emit_route_hash(route_h : Hash(YAML::Any, YAML::Any), details : Details, upstream : String)
      paths = array_of_strings(route_h[YAML::Any.new("paths")]?)
      return if paths.empty?

      # Kong routes without an explicit `methods` filter match all methods.
      # Noir represents that behavior with the synthetic `ANY` method label.
      methods = array_of_strings(route_h[YAML::Any.new("methods")]?).map(&.upcase)
      methods = ["ANY"] if methods.empty?
      hosts = array_of_strings(route_h[YAML::Any.new("hosts")]?)

      paths.each do |path|
        # We currently model Kong route path mode as regex (`~...`) vs non-regex.
        # Non-regex routes (including exact `=...`) are tagged as `prefix`.
        path_type = path.starts_with?("~") ? "regex" : "prefix"
        methods.each do |method|
          endpoint = Endpoint.new(path, method, details)
          endpoint.add_tag(Tag.new("kong-path-type", path_type, "kong_analyzer"))
          hosts.each { |host| endpoint.add_tag(Tag.new("kong-host", host, "kong_analyzer")) }
          endpoint.add_tag(Tag.new("kong-upstream", upstream, "kong_analyzer")) unless upstream.empty?
          @result << endpoint
        end
      end
    end

    private def array_of_strings(node : YAML::Any?) : Array(String)
      return [] of String if node.nil?

      if arr = node.as_a?
        arr.compact_map(&.as_s?).reject(&.empty?)
      elsif value = node.as_s?
        value.empty? ? [] of String : [value]
      else
        [] of String
      end
    end

    private def upstream_from(data_h : Hash(YAML::Any, YAML::Any)) : String
      if url = data_h[YAML::Any.new("url")]?.try(&.as_s?)
        return url unless url.empty?
      end

      if upstream_h = data_h[YAML::Any.new("upstream")]?.try(&.as_h?)
        host = upstream_h[YAML::Any.new("host")]?.try(&.to_s) || ""
        port = upstream_h[YAML::Any.new("port")]?.try(&.to_s) || ""
        return "#{host}:#{port}" if !host.empty? && !port.empty?
        return host unless host.empty?
      end

      host = data_h[YAML::Any.new("host")]?.try(&.to_s) || ""
      port = data_h[YAML::Any.new("port")]?.try(&.to_s) || ""
      return "#{host}:#{port}" if !host.empty? && !port.empty?
      return host unless host.empty?

      ""
    end
  end
end
