require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class CloudflareWrangler < Detector
    WRANGLER_FILES = {"wrangler.toml", "wrangler.jsonc", "wrangler.json"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      base = File.basename(filename)
      detected = case base
                 when "wrangler.toml"
                   file_contents.includes?("compatibility_date") ||
                     file_contents.includes?("[[routes]]") ||
                     file_contents.includes?("routes =")
                 when "wrangler.jsonc", "wrangler.json"
                   file_contents.includes?("compatibility_date") ||
                     file_contents.includes?("\"routes\"")
                 else
                   false
                 end

      CodeLocator.instance.push("cloudflare-wrangler-spec", filename) if detected
      detected
    end

    def applicable?(filename : String) : Bool
      WRANGLER_FILES.includes?(File.basename(filename))
    end

    def set_name
      @name = "cloudflare_wrangler"
    end

    # Registers each wrangler config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
