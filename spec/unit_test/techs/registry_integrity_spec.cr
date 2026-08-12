require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/techs/techs"
require "../../../src/detector/detector"
require "../../../src/analyzer/analyzer"
require "../../../src/tagger/tagger"
require "../../../src/models/logger"

# Tech identity lives in three hand-maintained lists with no compile-time
# linkage between them:
#
#   * `NoirTechs::TECHS`                 — the user-facing catalog behind
#                                          `noir list techs`, `-t`,
#                                          `--only-techs`, `--exclude-techs`
#   * `CALLEE_SUPPORTED_TECHS`           — `--include-callee` capability
#   * `AI_CONTEXT_GUARD_SUPPORTED_TECHS` — `--ai-context guards` capability
#
# It was five. The analyzer and detector registries are now derived from the
# classes themselves (`analyzer_for` / `detector_for`), so neither can be
# missing an entry — that is the shape the remaining three should end up in.
# Until then these specs are the linkage, and the analyzer/detector checks
# below prove the derivations still line up with the catalog rather than that
# two hand-written lists agree with each other.
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

# The tagger registry is derived from `Noir::TaggerFor` annotations rather
# than from a hand-maintained hash literal, but the derivation only sees
# classes that carry the annotation. A new tagger file that forgets it
# compiles, ships, and never runs — the exact failure the two literals used
# to have, moved one step. This sweep is what closes it.
describe "tagger registry integrity" do
  catalog = NoirTechs.techs.keys.map(&.to_s).to_set
  entries = NoirTaggers::ENTRIES
  keys = entries.map(&.key)

  it "annotates every concrete tagger class" do
    annotated = keys.to_set
    declared = [] of String

    # `Tagger::` is not a namespace here — taggers are top-level classes —
    # so the sweep excludes the two base classes by name instead. They stay
    # un-annotated on purpose: `spec/unit_test/models/tagger_spec.cr` and
    # `framework_tagger_spec.cr` instantiate them directly to exercise the
    # default `perform`, so neither can be made abstract.
    {% for sub in Tagger.all_subclasses %}
      {% unless sub.name == "FrameworkTagger" %}
        declared << {{ sub.stringify }}
      {% end %}
    {% end %}

    missing = [] of String
    {% for sub in Tagger.all_subclasses %}
      {% unless sub.name == "FrameworkTagger" || sub.annotation(Noir::TaggerFor) %}
        missing << {{ sub.stringify }}
      {% end %}
    {% end %}

    fail "tagger classes with no Noir::TaggerFor annotation (they will never run): #{sorted(missing)}" unless missing.empty?
    declared.size.should eq annotated.size
  end

  it "gives each tagger a unique key that is not the 'all' sentinel" do
    duplicates = keys.tally.select { |_, count| count > 1 }.keys
    fail "duplicate tagger keys: #{sorted(duplicates)}" unless duplicates.empty?
    keys.includes?("all").should be_false
  end

  it "gives every tagger a name and a description" do
    blank = entries.select { |entry| entry.name.blank? || entry.desc.blank? }.map(&.key)
    fail "taggers missing name/desc: #{sorted(blank)}" unless blank.empty?
  end

  it "reports each tagger's key as its runtime name" do
    # `run_tagger` selects by registry key and then logs failures by the
    # instance's `name`; the two disagreeing would make an unselectable
    # tagger, or a warning naming something the user never asked for.
    options = create_test_options
    mismatched = entries.compact_map do |entry|
      instance = NoirTaggers.build(entry.key, options)
      next "#{entry.key}: not constructible" if instance.nil?
      "#{entry.key}: name=#{instance.name}" unless instance.name == entry.key
    end
    fail "taggers whose runtime name differs from their registry key: #{mismatched}" unless mismatched.empty?
  end

  it "points every framework tagger at real catalog techs" do
    unknown = NoirTaggers.framework_taggers.flat_map do |entry|
      NoirTaggers.target_techs(entry.key).reject { |tech| catalog.includes?(tech) }
    end.uniq!
    fail "framework taggers target techs with no catalog entry: #{sorted(unknown)}" unless unknown.empty?
  end
end

# `:supersedes` moved the "when both are detected, X owns the routes" rules
# out of an `if` chain in `filter_redundant_generic_techs` and onto the
# superseding tech's catalog entry. A rule is now a data edge between two
# catalog keys, so it can be checked — the `if` chain could name a tech that
# no longer existed and nothing would notice.
describe "tech supersede integrity" do
  catalog = NoirTechs.techs.keys.map(&.to_s).to_set
  supersedes = NoirTechs::SUPERSEDES

  it "names only real techs on both ends of every rule" do
    unknown = supersedes.flat_map do |superseder, targets|
      ([superseder] + targets).reject { |tech| catalog.includes?(tech) }
    end.uniq!
    fail ":supersedes references techs with no catalog entry: #{sorted(unknown)}" unless unknown.empty?
  end

  it "never lets a tech supersede itself" do
    self_referential = supersedes.select { |superseder, targets| targets.includes?(superseder) }.keys
    fail "techs that supersede themselves: #{sorted(self_referential)}" unless self_referential.empty?
  end

  # What keeps `filter_redundant_generic_techs` order-independent. It
  # evaluates presence against its input rather than against the array it is
  # building, which is only equivalent to the old progressive form while no
  # chain exists. A chain would also be a design mistake in its own right:
  # if A supersedes B and B supersedes C, whether C survives depends on
  # whether A is present, which is not what either rule says.
  it "declares no supersede chains" do
    superseders = supersedes.keys.to_set
    chained = supersedes.flat_map { |_, targets| targets }.select { |target| superseders.includes?(target) }.uniq!
    fail "techs that are both a superseder and superseded: #{sorted(chained)}" unless chained.empty?
  end

  it "supersedes only techs that have an analyzer to suppress" do
    # A rule dropping a tech nothing analyzes is dead code that reads as a
    # live policy decision.
    logger = NoirLogger.new(false, false, false, true)
    analyzers = initialize_analyzers(logger).keys.to_set
    orphaned = supersedes.flat_map { |_, targets| targets }.reject { |t| analyzers.includes?(t) }.uniq!
    fail ":supersedes drops techs with no analyzer: #{sorted(orphaned)}" unless orphaned.empty?
  end
end
