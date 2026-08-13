require "../../spec_helper"
require "../../../src/techs/techs"

# `similar_to_tech` is how every tech-selection flag resolves a name: `-t`,
# `--only-techs`, `--exclude-techs`. Its middle step is a linear scan over
# `TECHS` that returns the *first* tech claiming the alias, so for any alias
# claimed by two techs the answer is decided by the order the catalog happens
# to be built in.
#
# That order is an implementation detail nobody should have to think about —
# and it has already changed once. Splitting the monolithic catalog into
# per-language files reordered insertion, and the aliases whose winner that
# silently flipped had to be found and pinned afterwards
# (`AMBIGUOUS_ALIAS_WINNERS`, added for exactly that reason).
#
# These examples make the order a free choice again by asserting the property
# rather than a snapshot: *no ambiguous alias may resolve by order*. Nothing
# here needs updating when a framework is added — only when a framework claims
# a name another framework already claims, which is precisely the case that
# needs a human decision rather than a coin toss.
#
# Companion to `registry_integrity_spec.cr`, which checks the analyzer /
# detector / catalog registries agree.

# alias (downcased) => every tech declaring it in `:similar`
private def alias_claims : Hash(String, Array(String))
  claims = {} of String => Array(String)
  NoirTechs::TECHS.each do |tech, info|
    similar = info[:similar]?
    next unless similar.is_a?(Array)
    similar.each do |name|
      (claims[name.to_s.downcase] ||= [] of String) << tech.to_s
    end
  end
  claims.each_value(&.uniq!)
  claims
end

private def tech_keys : Set(String)
  NoirTechs::TECHS.keys.map(&.to_s).to_set
end

describe "tech alias resolution" do
  it "resolves every canonical tech key to itself" do
    offenders = tech_keys.reject { |key| NoirTechs.similar_to_tech(key) == key }

    fail <<-MSG unless offenders.empty?
      every tech key must resolve to itself — `-t <key>` is the documented
      spelling. Techs that do not: #{offenders.to_a.sort}
      MSG
  end

  # The load-bearing one. An unpinned ambiguous alias resolves by catalog
  # order, which means reordering the catalog silently reassigns a
  # user-visible name.
  it "pins every alias that more than one tech claims" do
    ambiguous = alias_claims.select { |_, techs| techs.size > 1 }
    unpinned = ambiguous.reject do |name, _|
      # A pinned alias short-circuits the order-dependent scan; an alias that
      # is itself a tech key is resolved by the exact-key pass before it.
      NoirTechs::AMBIGUOUS_ALIAS_WINNERS.has_key?(name) || tech_keys.includes?(name)
    end

    fail <<-MSG unless unpinned.empty?
      these aliases are claimed by more than one tech and resolve by whatever
      order the catalog is built in, so a catalog reordering would silently
      hand the name to a different analyzer. Add each to
      `NoirTechs::AMBIGUOUS_ALIAS_WINNERS` naming the tech that should own it:
        #{unpinned.map { |name, techs| "#{name} <- #{techs.sort}" }.join("\n  ")}
      MSG
  end

  it "resolves every pinned alias to the tech it is pinned to" do
    offenders = NoirTechs::AMBIGUOUS_ALIAS_WINNERS.reject do |name, winner|
      NoirTechs.similar_to_tech(name) == winner
    end

    fail <<-MSG unless offenders.empty?
      a pin that does not take effect is worse than no pin — it reads as a
      decision while the order still decides. Offenders (alias => pinned):
        #{offenders.map { |a, w| "#{a} => #{w} (got #{NoirTechs.similar_to_tech(a)})" }.join("\n  ")}
      MSG
  end

  # A pin naming a tech that no longer exists resolves to a dead string, and
  # `-t <alias>` then selects nothing at all.
  it "pins only aliases that name a real tech" do
    offenders = NoirTechs::AMBIGUOUS_ALIAS_WINNERS.reject { |_, winner| tech_keys.includes?(winner) }

    fail <<-MSG unless offenders.empty?
      `AMBIGUOUS_ALIAS_WINNERS` names techs that are not in the catalog:
        #{offenders.map { |a, w| "#{a} => #{w}" }.join("\n  ")}
      MSG
  end

  # A pin for an alias only one tech claims is dead weight that reads as a
  # resolved dispute. It also hides the alias from the ambiguity check above:
  # if a second claimant appears later, the pin silently absorbs it.
  it "does not pin aliases that are not actually ambiguous" do
    claims = alias_claims
    offenders = NoirTechs::AMBIGUOUS_ALIAS_WINNERS.keys.reject do |name|
      (claims[name]?.try(&.size) || 0) > 1
    end

    fail <<-MSG unless offenders.empty?
      these pins are unnecessary — only one tech claims the alias, or no tech
      does: #{offenders.sort}
      MSG
  end

  # Guards the guard: a broken `alias_claims` would make the ambiguity check
  # pass vacuously, which is the failure mode that makes property specs
  # worthless.
  it "finds a non-trivial number of aliases to check" do
    claims = alias_claims
    claims.size.should be > 500
    claims.count { |_, techs| techs.size > 1 }.should be > 10
  end
end
