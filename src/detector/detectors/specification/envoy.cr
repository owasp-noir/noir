require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Envoy < Detector
    # Registers every matching config path in CodeLocator.
    detector_for "envoy", extensions: %w[.yaml .yml .json], idempotent: false

    # Every `.yaml`/`.yml`/`.json` in the tree reaches these gates.
    VIRTUAL_HOSTS_MARKER = /virtual_hosts/
    DOMAINS_MARKER       = /domains/

    # Envoy puts `virtual_hosts` at whatever depth the surrounding message
    # implies: at the document root for a standalone RouteConfiguration, one
    # level down under `route_config`, inside `resources[]` for an RDS
    # response, and — by far the most common in practice — buried under
    # `static_resources.listeners[].filter_chains[].filters[].typed_config.
    # route_config` in a bootstrap config. Searching the document instead of
    # enumerating layouts is what lets a plain `envoy.yaml` be recognised at
    # all. The bound only exists so a pathologically nested document can't
    # blow the stack; real configs sit around depth 8.
    MAX_SEARCH_DEPTH = 32

    # Hoisted so the per-node lookup in the walk below does not rebuild the
    # wrapper on every mapping it visits.
    VIRTUAL_HOSTS_KEY = YAML::Any.new("virtual_hosts")

    def detect(filename : String, file_contents : String) : Bool
      return false unless content_matches?(file_contents, VIRTUAL_HOSTS_MARKER) &&
                          content_matches?(file_contents, DOMAINS_MARKER)

      if filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        if (data = yaml_any?(file_contents)) && find_virtual_hosts_yaml(data)
          locator = CodeLocator.instance
          locator.push(Noir::LocatorKeys::ENVOY_YAML, filename)
          return true
        end
      elsif filename.ends_with?(".json")
        if (data = json_any?(file_contents)) && find_virtual_hosts_json(data)
          locator = CodeLocator.instance
          locator.push(Noir::LocatorKeys::ENVOY_JSON, filename)
          return true
        end
      end

      false
    end

    # A non-mapping node makes String-key `[]?` raise, so every lookup goes
    # through `as_h?` — the detector runs in a worker fiber with no rescue, and
    # a raise there kills the worker and loses results for this file.
    private def find_virtual_hosts_yaml(data : YAML::Any, depth : Int32 = 0) : Bool
      return false if depth > MAX_SEARCH_DEPTH

      if node = data.as_h?
        if vh = node[VIRTUAL_HOSTS_KEY]?
          return true if virtual_hosts_valid_yaml?(vh)
        end
        node.each_value { |value| return true if find_virtual_hosts_yaml(value, depth + 1) }
      elsif arr = data.as_a?
        arr.each { |value| return true if find_virtual_hosts_yaml(value, depth + 1) }
      end

      false
    end

    private def virtual_hosts_valid_yaml?(vh : YAML::Any) : Bool
      if arr = vh.as_a?
        arr.each do |host|
          next unless host.as_h?
          return true if host["domains"]?
        end
      end
      false
    end

    private def find_virtual_hosts_json(data : JSON::Any, depth : Int32 = 0) : Bool
      return false if depth > MAX_SEARCH_DEPTH

      if node = data.as_h?
        if vh = node["virtual_hosts"]?
          return true if virtual_hosts_valid_json?(vh)
        end
        node.each_value { |value| return true if find_virtual_hosts_json(value, depth + 1) }
      elsif arr = data.as_a?
        arr.each { |value| return true if find_virtual_hosts_json(value, depth + 1) }
      end

      false
    end

    private def virtual_hosts_valid_json?(vh : JSON::Any) : Bool
      if arr = vh.as_a?
        arr.each do |host|
          next unless host.as_h?
          return true if host["domains"]?
        end
      end
      false
    end
  end
end
