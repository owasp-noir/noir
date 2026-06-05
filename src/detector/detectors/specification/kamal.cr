require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Kamal < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless kamal_markers?(file_contents)
      return false unless kamal_config?(file_contents)

      CodeLocator.instance.push("kamal-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "kamal"
    end

    # Registers each Kamal config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    # Cheap substring pre-check ahead of the (relatively costly) YAML
    # parse. Kamal's two required keys are `service` and `image`, and a
    # real deploy file always also carries `servers` or `proxy`.
    private def kamal_markers?(content : String) : Bool
      content.includes?("service:") &&
        content.includes?("image:") &&
        (content.includes?("servers:") || content.includes?("proxy:"))
    end

    private def kamal_config?(content : String) : Bool
      root = YAML.parse(content).as_h?
      return false unless root

      # `service` and `image` are both required, scalar Kamal keys. The
      # singular `service` (vs Docker Compose's plural `services`) paired
      # with a top-level `image` string is what marks a Kamal deploy file.
      return false unless scalar_key?(root, "service")
      return false unless scalar_key?(root, "image")

      # A genuine Kamal file declares deploy targets (`servers`) and/or a
      # `proxy` block. Requiring one of these keeps generic YAMLs that
      # merely happen to carry `service`/`image` keys from matching.
      root.has_key?(YAML::Any.new("servers")) || root.has_key?(YAML::Any.new("proxy"))
    rescue
      false
    end

    private def scalar_key?(root : Hash(YAML::Any, YAML::Any), key : String) : Bool
      value = root[YAML::Any.new(key)]?
      return false if value.nil?
      !value.as_s?.nil?
    end
  end
end
