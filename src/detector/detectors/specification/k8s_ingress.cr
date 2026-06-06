require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class K8sIngress < Detector
    INGRESS_API_VERSION_PREFIXES = ["networking.k8s.io/", "extensions/v1beta1"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless ingress_markers_present?(file_contents)
      return false unless ingress_document_present?(file_contents)

      CodeLocator.instance.push("k8s-ingress-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "k8s_ingress"
    end

    # Registers each ingress manifest path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def ingress_document_present?(content : String) : Bool
      YAML.parse_all(content).any? do |doc|
        root = doc.as_h?
        next false unless root

        ingress_root?(root)
      end
    rescue
      # Helm/Kustomize templates often keep recognizable Ingress markers
      # while breaking strict YAML parsing with `{{ ... }}` expressions.
      # The analyzer has a tolerant fallback for these files.
      true
    end

    private def ingress_markers_present?(content : String) : Bool
      return false unless INGRESS_API_VERSION_PREFIXES.any? { |prefix| content.includes?(prefix) }

      has_api_version = false
      has_kind = false

      content.each_line do |line|
        normalized = normalize_manifest_line(line)
        if normalized.starts_with?("apiVersion:")
          has_api_version ||= supported_api_version?(line_value(normalized))
        elsif normalized.starts_with?("kind:")
          has_kind ||= line_value(normalized) == "Ingress"
        end

        return true if has_api_version && has_kind
      end

      false
    end

    private def supported_api_version?(api_version : String?) : Bool
      return false unless api_version

      api_version.starts_with?("networking.k8s.io/") || api_version == "extensions/v1beta1"
    end

    private def ingress_root?(root : Hash(YAML::Any, YAML::Any)) : Bool
      kind = root[YAML::Any.new("kind")]?.try(&.as_s?)
      if kind == "List"
        items = root[YAML::Any.new("items")]?.try(&.as_a?) || [] of YAML::Any
        return items.any? do |item|
          item_h = item.as_h?
          item_h ? ingress_root?(item_h) : false
        end
      end

      kind == "Ingress" && supported_api_version?(root[YAML::Any.new("apiVersion")]?.try(&.as_s?))
    end

    private def normalize_manifest_line(line : String) : String
      normalized = line.strip
      normalized = normalized[1..].strip if normalized.starts_with?("-")
      normalized
    end

    private def line_value(line : String) : String
      value = line.split(":", 2)[1]? || ""
      value = value.split("#", 2).first? || value
      value = value.strip

      if value.size >= 2
        first = value[0]
        last = value[value.size - 1]
        return value[1, value.size - 2] if (first == '"' && last == '"') || (first == '\'' && last == '\'')
      end

      value
    end
  end
end
