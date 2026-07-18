require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  # Payload CMS generates a REST surface from its collection and global
  # configs: `/api/<slug>` for collections, `/api/globals/<slug>` for
  # globals, plus whatever `endpoints: [...]` declares.
  #
  # `CollectionConfig` / `GlobalConfig` are types exported by the
  # `payload` package and appear essentially nowhere else, which is what
  # separates a Payload config from the many unrelated TS files that also
  # carry `slug:` and `fields:` (Astro content collections, Sanity
  # schemas, Keystone lists).
  #
  # The deliberate cost is plain-JS configs with no type annotation.
  # Matching bare `slug:` + `fields:` would trip on all three of the
  # above, so that gap is accepted.
  class PayloadCms < Detector
    CONFIG_EXTENSIONS = {".ts", ".tsx", ".js", ".mjs", ".cjs", ".mts", ".cts"}

    # Single combined gate, checked before anything else. This detector is
    # applicable to every JS/TS file in the tree and is non-idempotent, so
    # `detect` runs on all of them for the whole scan — and vendored
    # bundles (`compiled/*.min.js`) can be megabytes each. Running the
    # individual markers unconditionally meant three full scans per file
    # and cost ~4x the total scan time on a large TS monorepo.
    PAYLOAD_MARKER = /\bCollectionConfig\b|\bGlobalConfig\b|\bbuildConfig\s*\(/

    COLLECTION_MARKER = /\bCollectionConfig\b/
    GLOBAL_MARKER     = /\bGlobalConfig\b/
    BUILD_CONFIG      = /\bbuildConfig\s*\(/

    # A config object always declares both.
    SLUG_MARKER   = /\bslug\s*:\s*['"]/
    FIELDS_MARKER = /\bfields\s*:\s*\[/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.matches?(PAYLOAD_MARKER)

      detected = false

      if file_contents.matches?(COLLECTION_MARKER) &&
         file_contents.matches?(SLUG_MARKER) && file_contents.matches?(FIELDS_MARKER)
        CodeLocator.instance.push("payload-collection", filename)
        detected = true
      end

      if file_contents.matches?(GLOBAL_MARKER) &&
         file_contents.matches?(SLUG_MARKER) && file_contents.matches?(FIELDS_MARKER)
        CodeLocator.instance.push("payload-global", filename)
        detected = true
      end

      if file_contents.matches?(BUILD_CONFIG)
        CodeLocator.instance.push("payload-config", filename)
        detected = true
      end

      detected
    end

    def applicable?(filename : String) : Bool
      path = filename.includes?('\\') ? filename.gsub('\\', '/') : filename
      # Declaration files carry the type without ever declaring a config,
      # and test files describe configs they do not serve.
      return false if path.ends_with?(".d.ts")
      return false if path.includes?(".test.") || path.includes?(".spec.")

      CONFIG_EXTENSIONS.includes?(File.extname(path).downcase)
    end

    def set_name
      @name = "payload_cms"
    end

    # Registers every collection, global and config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
