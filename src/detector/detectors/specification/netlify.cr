require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Netlify < Detector
    # Registers file paths for analyzer pass.
    detector_for "netlify", idempotent: false

    REDIRECTS_FILE = "_redirects"
    TOML_FILE      = "netlify.toml"

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      locator = CodeLocator.instance

      case base
      when REDIRECTS_FILE
        locator.push("netlify-redirects", filename)
        true
      when TOML_FILE
        locator.push("netlify-toml", filename)
        true
      else
        false
      end
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      base == REDIRECTS_FILE || base == TOML_FILE
    end
  end
end
