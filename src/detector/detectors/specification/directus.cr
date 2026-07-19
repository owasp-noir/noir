require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  # `directus schema snapshot` writes the whole data model - collections,
  # fields and relations - to a single file, and Directus generates its
  # `/items/<collection>` REST surface from exactly that model.
  #
  # A snapshot always carries a root `directus:` key holding the engine
  # version that produced it. That key is what separates a real snapshot
  # from any other document with `collections:` and `fields:` (Sanity
  # exports, MongoDB configs, CI matrices), so it is required rather than
  # merely preferred.
  class Directus < Detector
    SNAPSHOT_EXTENSIONS = {".yaml", ".yml", ".json"}

    # Cheap gate before libyaml: one precompiled alternation beats
    # chained String#includes? on Crystal (see analyzers/php/php.cr).
    SNAPSHOT_MARKER = /^\s*directus\s*:|"directus"\s*:/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.matches?(SNAPSHOT_MARKER)

      data = yaml_any?(file_contents)
      return false unless data
      root = data.as_h?
      return false unless root

      # The version string identifies the producing engine.
      return false unless root[YAML::Any.new("directus")]?
      return false unless collections_present?(root)

      CodeLocator.instance.push("directus-snapshot", filename)
      true
    end

    # libyaml parses JSON as a YAML subset, so one code path covers the
    # `--format json` snapshot too.
    # Memo safety: `applicable?` consults the path
    # (/directus/ and /snapshots/ gates), not just the basename.
    def path_sensitive? : Bool
      true
    end

    def applicable?(filename : String) : Bool
      return false unless SNAPSHOT_EXTENSIONS.includes?(File.extname(filename).downcase)

      path = filename.includes?('\\') ? filename.gsub('\\', '/') : filename
      File.basename(path).downcase.starts_with?("snapshot") ||
        path.includes?("/directus/") ||
        path.includes?("/snapshots/")
    end

    def set_name
      @name = "directus"
    end

    # Registers each snapshot path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def collections_present?(root : Hash(YAML::Any, YAML::Any)) : Bool
      entries = root[YAML::Any.new("collections")]?.try(&.as_a?)
      return false unless entries

      entries.any? do |entry|
        entry.as_h?.try(&.has_key?(YAML::Any.new("collection"))) || false
      end
    end
  end
end
