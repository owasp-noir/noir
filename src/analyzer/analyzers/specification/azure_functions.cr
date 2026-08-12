require "../../engines/specification_engine"

module Analyzer::Specification
  class AzureFunctions < SpecificationEngine
    analyzer_for "azure_functions"

    METHOD_ANY = "ANY"

    # The Functions host serves every HTTP-triggered function under a route
    # prefix. `host.json` may override it (`""` disables it entirely), but when
    # the key is absent the host still applies `api` — so a function with
    # `"route": "products/{id}"` answers on `/api/products/{id}`, not
    # `/products/{id}`.
    DEFAULT_ROUTE_PREFIX = "api"

    def analyze
      # `host.json` sits at the function-app root, one level above each
      # function's own directory, and is shared by every function in the app.
      # Resolve it once per app root instead of per function.
      prefixes = {} of String => String

      each_spec_file_with_details(Noir::LocatorKeys::AZURE_FUNCTIONS_SPEC) do |path, details|
        content = read_file_content(path)
        app_root = File.dirname(File.dirname(path))
        prefix = prefixes[app_root] ||= route_prefix_for(app_root)
        process_doc(JSON.parse(content), path, prefix, details)
      end

      @result
    end

    # Reads `extensions.http.routePrefix` (Functions v2+) or the v1 `http.routePrefix`
    # from the app's `host.json`. An unreadable or absent file leaves the host default.
    private def route_prefix_for(app_root : String) : String
      host_json = File.join(app_root, "host.json")
      return DEFAULT_ROUTE_PREFIX unless File.exists?(host_json)

      doc = JSON.parse(read_file_content(host_json))
      http = doc["extensions"]?.try(&.as_h?).try(&.["http"]?) || doc["http"]?
      value = http.try(&.as_h?).try(&.["routePrefix"]?).try(&.as_s?)
      return DEFAULT_ROUTE_PREFIX if value.nil?

      value.strip('/')
    rescue e
      @logger.debug "Azure Functions analyzer failed to read #{host_json}"
      @logger.debug_sub e
      DEFAULT_ROUTE_PREFIX
    end

    private def process_doc(doc : JSON::Any, path : String, route_prefix : String, details : Details)
      bindings = doc["bindings"]?.try(&.as_a?)
      return unless bindings

      function_name = File.basename(File.dirname(path))

      bindings.each do |binding|
        binding_h = binding.as_h?
        next unless binding_h

        type = binding_h["type"]?.try(&.as_s?) || ""
        next unless type == "httpTrigger"

        methods = extract_methods(binding_h["methods"]?)
        methods = [METHOD_ANY] if methods.empty?

        route = binding_h["route"]?.try(&.as_s?) || function_name
        normalized_path = compose_path(route_prefix, route)

        auth_level = binding_h["authLevel"]?.try(&.as_s?)

        methods.each do |method|
          endpoint = Endpoint.new(normalized_path, method, details)
          endpoint.add_tag(Tag.new("azure-function-name", function_name, "azure_functions_analyzer"))
          endpoint.add_tag(Tag.new("azure-auth-level", auth_level, "azure_functions_analyzer")) if auth_level && !auth_level.empty?
          @result << endpoint
        end
      end
    end

    private def compose_path(route_prefix : String, route : String) : String
      cleaned = route.starts_with?('/') ? route : "/#{route}"
      return cleaned if route_prefix.empty?
      "/#{route_prefix}#{cleaned}"
    end

    private def extract_methods(node : JSON::Any?) : Array(String)
      return [] of String if node.nil?
      arr = node.as_a?
      return [] of String unless arr
      arr.compact_map(&.as_s?).reject(&.empty?).map(&.upcase)
    end
  end
end
