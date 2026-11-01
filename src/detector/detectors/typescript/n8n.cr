require "../../../models/detector"

module Detector::Typescript
  # n8n's controller decorators, `@n8n/decorators` (`@RestController`,
  # `@RootLevelController`, `@PublicApiController`).
  class N8n < Detector
    detector_for "ts_n8n",
      extensions: %w[.ts],
      basenames: %w[package.json]

    PACKAGE_RE = /"@n8n\/decorators"\s*:/
    IMPORT_RE  = /(?:\bfrom|\brequire\s*\()\s*['"]@n8n\/decorators['"]/

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return content_matches?(file_contents, PACKAGE_RE)
      end

      filename.ends_with?(".ts") && content_matches?(file_contents, IMPORT_RE)
    end
  end
end
