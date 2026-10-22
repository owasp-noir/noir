require "../../../models/detector"

module Detector::Typescript
  class Wasp < Detector
    detector_for "ts_wasp", extensions: %w[.wasp .ts], basenames: %w[.wasproot]

    # Wasp DSL: every app has exactly one `app <name> { wasp: { version } }`.
    DSL_APP     = /^\s*app\s+[A-Za-z_]\w*\s*\{/m
    DSL_VERSION = /\bwasp\s*:\s*\{\s*version\s*:/
    # Wasp Spec (0.24+) and the earlier preview TS config.
    TS_IMPORT = /from\s*['"](?:@wasp\.sh\/spec|wasp-config)['"]/

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      # `wasp new` writes this marker at the project root.
      return true if base == ".wasproot"
      relative = base_relative_path(filename)
      return false if relative.includes?("/.wasp/") || relative.includes?("/node_modules/")

      if filename.ends_with?(".wasp")
        file_contents.matches?(DSL_APP) && file_contents.matches?(DSL_VERSION)
      elsif base.ends_with?(".wasp.ts")
        file_contents.includes?("wasp") && file_contents.matches?(TS_IMPORT)
      else
        false
      end
    end
  end
end
