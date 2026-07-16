require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class Traefik < Detector
    # Necessary-condition guard for the YAML branch: every accepted shape
    # requires one of these literals in the raw document — a `routers` key
    # (`traefik_dynamic_config?`, and the `traefik.http.routers.` label
    # fallback contains it too), a `kind: IngressRoute`, or a
    # `traefik.io/` apiVersion. Any YAML file without them skips the full
    # parse (this detector is non-idempotent and previously parsed every
    # YAML file of the scan twice).
    YAML_MARKER = /routers|IngressRoute|traefik\.io\//

    def detect(filename : String, file_contents : String) : Bool
      check = false

      if filename.ends_with?(".toml")
        check = file_contents.includes?("[http.routers.") && file_contents.includes?("rule")
      elsif (filename.ends_with?(".yaml") || filename.ends_with?(".yml")) && file_contents.matches?(YAML_MARKER)
        if data = yaml_any?(file_contents)
          begin
            check = traefik_dynamic_config?(data) ||
                    ingress_route?(data) ||
                    file_contents.includes?("traefik.http.routers.")
          rescue
            check = file_contents.includes?("traefik.http.routers.")
          end
        end
      end

      if check
        locator = CodeLocator.instance
        locator.push("traefik-spec", filename)
      end

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml") || filename.ends_with?(".toml")
    end

    def set_name
      @name = "traefik"
    end

    # Registers every Traefik config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def traefik_dynamic_config?(data : YAML::Any) : Bool
      return false unless root = data.as_h?
      http = root[YAML::Any.new("http")]?
      return false unless http_h = http.try(&.as_h?)
      routers = http_h[YAML::Any.new("routers")]?
      !routers.nil? && !!routers.try(&.as_h?)
    end

    private def ingress_route?(data : YAML::Any) : Bool
      return false unless root = data.as_h?
      kind = root[YAML::Any.new("kind")]?.try(&.to_s) || ""
      return true if kind == "IngressRoute"
      api_version = root[YAML::Any.new("apiVersion")]?.try(&.to_s) || ""
      api_version.includes?("traefik.io/")
    end
  end
end
