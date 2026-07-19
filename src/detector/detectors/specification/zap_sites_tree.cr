require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class ZapSitesTree < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      # The accepted shape requires a "node" value containing "Sites", so
      # the literal must appear in the raw document — guard before the full
      # parse (this detector is non-idempotent and previously parsed every
      # YAML file of the scan twice).
      if applicable?(filename) && file_contents.includes?("Sites") && (data = yaml_any?(file_contents))
        begin
          if data[0]["node"].as_s.includes? "Sites"
            check = true
            locator = CodeLocator.instance
            locator.push("zap-sites-tree", filename)
          end
        rescue e
          logger.debug "ZAP sites-tree detection failed for #{filename}: #{e}"
        end
      end

      check
    end

    def applicable?(filename : String) : Bool
      # Extension only. A `*sites*` basename gate looks tempting, but ZAP
      # export filenames are chosen by the user at export time — an export
      # saved as `zap_export.yaml` or `target.yaml` would be dropped with
      # no diagnostic. The expensive work (`yaml_any?`) is already gated
      # in `detect` by the `includes?("Sites")` content guard, so the name
      # gate only saved a substring scan and bought that at the price of a
      # silent false negative.
      filename.ends_with?(".yaml") || filename.ends_with?(".yml")
    end

    def set_name
      @name = "zap_sites_tree"
    end

    # Registers ZAP sites-tree paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
