require "../../../models/detector"

module Detector::Javascript
  # Egg.js names itself in package.json (the `egg` dependency, the
  # `egg-bin` / `@eggjs/bin` runner or the `"egg": { ... }` config block);
  # TypeScript apps also import their types from `egg`.
  class Egg < Detector
    detector_for "js_egg",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    PACKAGE_MARKER = /"(?:egg|egg-core|egg-bin|@eggjs\/bin)"\s*:|(?:\brequire\s*\(\s*|\bfrom\s+)['"]egg['"]/

    def detect(filename : String, file_contents : String) : Bool
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
