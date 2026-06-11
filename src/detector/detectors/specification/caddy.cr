require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Caddy < Detector
    CADDYFILE_NAMES = {"Caddyfile", "caddyfile"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      base = File.basename(filename)
      if CADDYFILE_NAMES.includes?(base)
        CodeLocator.instance.push("caddy-spec", filename)
        true
      elsif filename.ends_with?(".json")
        return false unless caddy_json?(file_contents)
        JSON.parse(file_contents)
        CodeLocator.instance.push("caddy-spec", filename)
        true
      else
        false
      end
    rescue
      false
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      CADDYFILE_NAMES.includes?(base) || filename.ends_with?(".json")
    end

    def set_name
      @name = "caddy"
    end

    # Registers each Caddy config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def caddy_json?(content : String) : Bool
      # JSON-format Caddy configs always nest the HTTP app under
      # `apps.http`. Use that shape as the discriminator so we don't
      # claim every JSON file that happens to be in the tree.
      content.includes?("\"apps\"") && content.includes?("\"http\"")
    end
  end
end
