require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Kong < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_yaml?(file_contents)

      begin
        data = YAML.parse(file_contents)
        if kong_doc?(data)
          CodeLocator.instance.push("kong-spec", filename)
          return true
        end
      rescue e
        logger.debug "Kong detection failed for #{filename}: #{e}"
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "kong"
    end

    def idempotent? : Bool
      false
    end

    private def kong_doc?(data : YAML::Any) : Bool
      if data_h = data.as_h?
        return true if deck_shape?(data_h)
        return true if kic_shape?(data_h)

        if items = data_h[YAML::Any.new("items")]?.try(&.as_a?)
          return items.any? { |item| kong_doc?(item) }
        end
      elsif data_a = data.as_a?
        return data_a.any? { |item| kong_doc?(item) }
      end

      false
    end

    private def deck_shape?(data_h : Hash(YAML::Any, YAML::Any)) : Bool
      has_format_version = data_h.has_key?(YAML::Any.new("_format_version"))
      has_services = !data_h[YAML::Any.new("services")]?.try(&.as_a?).nil?
      has_format_version && has_services
    end

    private def kic_shape?(data_h : Hash(YAML::Any, YAML::Any)) : Bool
      api_version = data_h[YAML::Any.new("apiVersion")]?.try(&.to_s) || ""
      kind = data_h[YAML::Any.new("kind")]?.try(&.to_s) || ""
      return false unless api_version.includes?("configuration.konghq.com/")
      {"KongIngress", "KongRoute"}.includes?(kind)
    end
  end
end
