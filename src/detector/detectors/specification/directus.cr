require "../../../models/file_role"
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
    # Registers each snapshot path in `CodeLocator`.
    # libyaml parses JSON as a YAML subset, so one code path covers the
    # `--format json` snapshot too.
    # Memo safety: `applicable?` consults the path
    # (/directus/ and /snapshots/ gates), not just the basename.
    detector_for "directus", idempotent: false, path_sensitive: true

    SNAPSHOT_EXTENSIONS = {".yaml", ".yml", ".json"}

    # Cheap gate before libyaml: one precompiled alternation beats
    # chained String#includes? on Crystal (see analyzers/php/php.cr).
    SNAPSHOT_MARKER = /^\s*directus\s*:|"directus"\s*:/m

    # Test directories, mocks, and fixtures that contain temporary/generated schema snapshots
    # for test suites rather than the project's production schema.
    SNAPSHOT_TEST = Noir::FileRole::Convention.new(:test,
      path: Regex.union("/tests/", "/test/", "/__tests__/", "/e2e/", "/e2e-tests/",
        "/cypress/", "/playwright/", "/__mocks__/", "/__fixtures__/", "/fixtures/", "/fixture/", "/spec/", "/specs/"),
      name: Regex.union(".test.", ".spec.", "-test.", "-spec.", "_test.", "_spec."))

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless content_matches?(file_contents, SNAPSHOT_MARKER)

      data = yaml_any?(file_contents)
      return false unless data
      root = data.as_h?
      return false unless root

      # The version string identifies the producing engine.
      return false unless root[YAML::Any.new("directus")]?
      return false unless collections_present?(root)

      CodeLocator.instance.push(Noir::LocatorKeys::DIRECTUS_SNAPSHOT, filename)
      true
    end

    def applicable?(filename : String) : Bool
      return false unless SNAPSHOT_EXTENSIONS.includes?(File.extname(filename).downcase)

      path = filename.gsub('\\', '/')

      relative = base_relative_path(path)
      relative_path = relative.starts_with?('/') ? relative : "/#{relative}"

      name = File.basename(path).downcase
      return false if Noir::FileRole.classify(relative_path, SNAPSHOT_TEST, filename: name).test?

      name.starts_with?("snapshot") ||
        relative_path.includes?("/directus/") ||
        relative_path.includes?("/snapshots/")
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
