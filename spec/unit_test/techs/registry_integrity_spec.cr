require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/techs/techs"
require "../../../src/detector/detector"
require "../../../src/analyzer/analyzer"
require "../../../src/models/logger"

# Tech identity lives in four hand-maintained lists with no compile-time
# linkage between them:
#
#   * `NoirTechs::TECHS`                 — the user-facing catalog behind
#                                          `noir list techs`, `-t`,
#                                          `--only-techs`, `--exclude-techs`
#   * `define_analyzers` (analyzer.cr)   — tech -> analyzer
#   * `CALLEE_SUPPORTED_TECHS`           — `--include-callee` capability
#   * `AI_CONTEXT_GUARD_SUPPORTED_TECHS` — `--ai-context guards` capability
#
# It was five. `build_detector_list` is now derived from the `Detector::`
# subclasses themselves, so a detector cannot be missing from it — which is
# the shape the remaining four should end up in. Until then these specs stay
# the linkage, and the detector checks below are what proves the derivation
# still lines up with the catalog.
#
# Nothing forced them to agree, and they drifted in both directions:
# `zap_sites_tree` shipped a working analyzer *and* detector but no catalog
# entry, so all three tech-selection flags rejected a technology noir
# actually supports and `noir list techs` never mentioned it; `:graphql` sat
# in the catalog with neither an analyzer nor a detector behind it, and its
# `"graphql"` alias shadowed lookups that belong to `graphql_sdl`.
#
# These specs are that missing linkage. A tech added to one list but not the
# others fails here rather than shipping as a silent capability gap.

# Analyzers that intentionally have no detector and no catalog entry.
DYNAMIC_ANALYZER_TECHS = Set{
  # Activated by `--ai-provider`, never by file detection. Kept out of the
  # catalog so it is not offered as a `-t` target.
  "ai",
}

private def sorted(names) : Array(String)
  names.to_a.sort
end

describe "tech registry integrity" do
  logger = NoirLogger.new(false, false, false, true)

  catalog = NoirTechs.techs.keys.map(&.to_s).to_set
  analyzers = initialize_analyzers(logger).keys.to_set - DYNAMIC_ANALYZER_TECHS
  detectors = build_detector_list(create_test_options).map(&.name).to_set

  it "gives every analyzer a catalog entry" do
    # Without one, `-t <tech>` / `--only-techs <tech>` / `--exclude-techs
    # <tech>` all reject the name and `noir list techs` omits it.
    orphans = analyzers - catalog
    fail "analyzers with no NoirTechs::TECHS entry: #{sorted(orphans)}" unless orphans.empty?
  end

  it "gives every detector a catalog entry" do
    orphans = detectors - catalog
    fail "detectors with no NoirTechs::TECHS entry: #{sorted(orphans)}" unless orphans.empty?
  end

  it "backs every catalog entry with an analyzer" do
    # A catalog entry with no analyzer advertises a capability that cannot
    # produce endpoints.
    phantoms = catalog - analyzers
    fail "NoirTechs::TECHS entries with no analyzer: #{sorted(phantoms)}" unless phantoms.empty?
  end

  it "backs every catalog entry with a detector" do
    phantoms = catalog - detectors
    fail "NoirTechs::TECHS entries with no detector: #{sorted(phantoms)}" unless phantoms.empty?
  end

  it "registers each detector name exactly once" do
    names = build_detector_list(create_test_options).map(&.name)
    dupes = names.tally.select { |_, count| count > 1 }.keys
    fail "detector names registered more than once: #{sorted(dupes)}" unless dupes.empty?
  end

  it "names only real techs in CALLEE_SUPPORTED_TECHS" do
    unknown = NoirTechs::CALLEE_SUPPORTED_TECHS.to_set - catalog
    fail "CALLEE_SUPPORTED_TECHS names unknown techs: #{sorted(unknown)}" unless unknown.empty?
  end

  it "names only real techs in AI_CONTEXT_GUARD_SUPPORTED_TECHS" do
    unknown = NoirTechs::AI_CONTEXT_GUARD_SUPPORTED_TECHS.to_set - catalog
    fail "AI_CONTEXT_GUARD_SUPPORTED_TECHS names unknown techs: #{sorted(unknown)}" unless unknown.empty?
  end

  it "resolves every catalog key through similar_to_tech" do
    # `similar_to_tech` is the single gate every tech-selection flag passes
    # through. A key it cannot round-trip is unreachable from the CLI.
    unresolvable = catalog.reject { |tech| NoirTechs.similar_to_tech(tech) == tech }
    fail "catalog keys similar_to_tech cannot resolve: #{sorted(unresolvable)}" unless unresolvable.empty?
  end
end
