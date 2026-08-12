require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class RAML < Detector
    # Registers RAML spec paths in `CodeLocator`.
    detector_for "raml", extensions: %w[.raml .yaml .yml], idempotent: false

    # Every `.raml`/`.yaml`/`.yml` in the tree reaches this guard.
    RAML_MARKER = /\#%RAML/

    def detect(filename : String, file_contents : String) : Bool
      check = false
      if filename.ends_with?(".raml") || filename.ends_with?(".yaml") || filename.ends_with?(".yml")
        if content_matches?(file_contents, RAML_MARKER)
          # `valid_yaml?` already proves the content parses; the previous
          # second `YAML.parse` (result discarded) doubled the cost for
          # nothing.
          if valid_yaml?(file_contents)
            check = true
            locator = CodeLocator.instance
            locator.push(Noir::LocatorKeys::RAML_SPEC, filename)
          end
        end
      end

      check
    end
  end
end
