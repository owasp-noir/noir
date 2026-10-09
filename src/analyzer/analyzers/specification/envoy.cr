require "../../engines/specification_engine"

module Analyzer::Specification
  # Extracts HTTP endpoints from Envoy proxy route configuration files
  # (YAML or JSON). `virtual_hosts` is collected from wherever it sits in the
  # document, because Envoy nests it differently per layout:
  #   - at the root (xDS RDS RouteConfiguration)
  #   - under `route_config` (standalone static RouteConfiguration)
  #   - under `resources[]` (xDS resource array)
  #   - under `static_resources.listeners[].filter_chains[].filters[].
  #     typed_config.route_config` (bootstrap config — the everyday shape;
  #     30 of the 31 `virtual_hosts` YAMLs in envoyproxy/envoy look like this)
  #
  # For each route the analyzer extracts:
  #   - Path from `match.prefix`, `match.path`, `match.path_separated_prefix`
  #     or `match.safe_regex.regex`
  #   - HTTP method from `match.headers[]` where `name: ":method"`
  #   - An additional endpoint for `route.prefix_rewrite` when it differs
  #     from the matched path
  class Envoy < SpecificationEngine
    analyzer_for "envoy"

    # See the detector's constant of the same name: a bound that only exists so
    # a pathologically nested document can't blow the stack. Real configs sit
    # around depth 8.
    MAX_SEARCH_DEPTH = 32

    # Hoisted so the per-node lookups in the walks below do not rebuild the
    # wrappers on every mapping they visit.
    VIRTUAL_HOSTS_KEY = YAML::Any.new("virtual_hosts")
    DOMAINS_KEY       = YAML::Any.new("domains")
    ROUTES_KEY        = YAML::Any.new("routes")
    MATCH_KEY         = YAML::Any.new("match")
    ROUTE_KEY         = YAML::Any.new("route")

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::ENVOY_YAML) do |path, details|
        content = read_file_content(path)
        process_yaml(YAML.parse(content), details)
      end

      each_spec_file_with_details(Noir::LocatorKeys::ENVOY_JSON) do |path, details|
        content = read_file_content(path)
        process_json(parse_json_lenient(content), details)
      end

      @result
    end

    # ── YAML processing ──────────────────────────────────────────────────────

    private def process_yaml(data : YAML::Any, details : Details)
      virtual_hosts = [] of YAML::Any
      collect_virtual_hosts_yaml(data, virtual_hosts)

      virtual_hosts.each do |vh|
        next unless vh_h = vh.as_h?
        domains = domain_list(vh_h[DOMAINS_KEY]?)
        if routes_node = vh_h[ROUTES_KEY]?
          if routes = routes_node.as_a?
            routes.each { |route| process_route_yaml(route, domains, details) }
          end
        end
      end
    end

    private def collect_virtual_hosts_yaml(data : YAML::Any, sink : Array(YAML::Any), depth : Int32 = 0)
      return if depth > MAX_SEARCH_DEPTH

      if node = data.as_h?
        if vh = node[VIRTUAL_HOSTS_KEY]?.try(&.as_a?)
          sink.concat(vh)
        end
        node.each_value { |value| collect_virtual_hosts_yaml(value, sink, depth + 1) }
      elsif arr = data.as_a?
        arr.each { |value| collect_virtual_hosts_yaml(value, sink, depth + 1) }
      end
    end

    private def process_route_yaml(route : YAML::Any, domains : Array(String), details : Details)
      return unless route_h = route.as_h?
      return unless match = route_h[MATCH_KEY]?

      path = extract_path(match)
      return if path.nil? || path.empty?

      method = extract_method(match) || "GET"
      emit(path, method, domains, details)

      if (route_action = route_h[ROUTE_KEY]?) && route_action.as_h?
        if rewrite = route_action["prefix_rewrite"]?.try(&.as_s?)
          emit(rewrite, method, domains, details) unless rewrite == path
        end
      end
    end

    # ── JSON processing ───────────────────────────────────────────────────────

    private def process_json(data : JSON::Any, details : Details)
      virtual_hosts = [] of JSON::Any
      collect_virtual_hosts_json(data, virtual_hosts)

      virtual_hosts.each do |vh|
        next unless vh_h = vh.as_h?
        domains = domain_list(vh_h["domains"]?)
        if routes_node = vh_h["routes"]?
          if routes = routes_node.as_a?
            routes.each { |route| process_route_json(route, domains, details) }
          end
        end
      end
    end

    private def collect_virtual_hosts_json(data : JSON::Any, sink : Array(JSON::Any), depth : Int32 = 0)
      return if depth > MAX_SEARCH_DEPTH

      if node = data.as_h?
        if vh = node["virtual_hosts"]?.try(&.as_a?)
          sink.concat(vh)
        end
        node.each_value { |value| collect_virtual_hosts_json(value, sink, depth + 1) }
      elsif arr = data.as_a?
        arr.each { |value| collect_virtual_hosts_json(value, sink, depth + 1) }
      end
    end

    private def process_route_json(route : JSON::Any, domains : Array(String), details : Details)
      return unless route_h = route.as_h?
      return unless match = route_h["match"]?

      path = extract_path(match)
      return if path.nil? || path.empty?

      method = extract_method(match) || "GET"
      emit(path, method, domains, details)

      if (route_action = route_h["route"]?) && route_action.as_h?
        if rewrite = route_action["prefix_rewrite"]?.try(&.as_s?)
          emit(rewrite, method, domains, details) unless rewrite == path
        end
      end
    end

    # ── Shared helpers ────────────────────────────────────────────────────────

    private def domain_list(node) : Array(String)
      return [] of String if node.nil?
      return [] of String unless arr = node.as_a?
      arr.compact_map(&.as_s?).reject { |d| d.empty? || d == "*" }
    end

    private def extract_path(match) : String?
      return unless match.as_h?
      if prefix = match["prefix"]?.try(&.as_s?)
        return prefix
      end
      if path = match["path"]?.try(&.as_s?)
        return path
      end
      # `path_separated_prefix` matches the prefix on a `/` boundary. It is a
      # distinct match type in the proto, so a route that uses it was invisible.
      if separated = match["path_separated_prefix"]?.try(&.as_s?)
        return separated
      end
      if (safe_regex = match["safe_regex"]?) && safe_regex.as_h?
        return safe_regex["regex"]?.try(&.as_s?).try { |regex| Noir::URLPath.strip_regex_anchors(regex) }
      end
      # Envoy v2 legacy field
      match["regex"]?.try(&.as_s?).try { |regex| Noir::URLPath.strip_regex_anchors(regex) }
    end

    private def extract_method(match) : String?
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

    # The optimizer dedupes on (method, url), so emitting one endpoint per
    # domain would drop every domain but the first. Fold them into a single
    # comma-joined tag instead — same shape as the kamal and apisix analyzers.
    private def emit(url : String, method : String, domains : Array(String), details : Details)
      endpoint = Endpoint.new(url, method, details)
      endpoint.add_tag(Tag.new("envoy-domain", domains.join(", "), "envoy_analyzer")) unless domains.empty?
      @result << endpoint
    end
  end
end
