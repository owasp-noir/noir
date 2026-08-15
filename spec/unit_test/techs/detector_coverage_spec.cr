require "../../spec_helper"

# Every detector registered with `detector_for` must have a unit spec.
#
# The registry is derived from the classes, so a detector joins a scan simply by
# existing (`build_detector_list`, src/detector/detector.cr). That removed the
# "forgot to register it" failure mode and replaced it with a quieter one:
# nothing at all requires a detector to be *tested*. 64 of 244 — including
# `rust/actix_web`, `java/quarkus`, `java/micronaut`, `java/jaxrs`,
# `javascript/hapi`, `swift/hummingbird`, `typescript/trpc`, every `zig/*` and
# every language's `cli` — shipped with zero coverage.
#
# A detector is the gate in front of an analyzer: when it is wrong the analyzer
# never runs, and the scan reports an absence rather than an error. That is the
# hardest kind of regression to notice, and the most likely to arrive with a
# volume of parallel contributions.
#
# This is a *ratchet*. The list below is the debt as it stood when the check
# landed; entries may be deleted, never added. A new detector without a spec
# fails here.
#
# ## Deliberately detectors only
#
# The analyzer side has no equivalent check, and that is a considered decision
# rather than an oversight. `spec/functional_test/fixtures/{lang}/{fw}/` is not
# a convention the tree follows: `clojure/cli`'s fixtures are `cli_argparse`,
# `elixir/elixir_phoenix.cr`'s are `elixir/phoenix`, and Go's CLI analyzer has
# ten `cli_*` directories. A path-equality check produces ~24 false positives,
# and the prefix-matching needed to fix that would be a rule loose enough to
# pass on an unrelated directory. Renaming two dozen fixture directories to
# make a check tidy is the tail wagging the dog; if the analyzer side gets a
# check later, it wants a real signal (which techs actually produced endpoints)
# rather than a filename convention.

# Repo-relative glob: `crystal spec` runs from the repository root, the same
# assumption as options_boundary_spec.cr and layering_boundary_spec.cr.
private def detector_paths : Array(String)
  Dir.glob("src/detector/detectors/**/*.cr")
    .select { |path| File.read(path).matches?(/^\s*detector_for\s/m) }
    .map { |path| path.sub("src/detector/detectors/", "").sub(/\.cr$/, "") }
    .sort!
end

private def spec_path_for(detector : String) : String
  "spec/unit_test/detector/#{detector}_spec.cr"
end

# Detectors that had no unit spec when this check landed. Shrink only.
#
# Each is a real gap, not an exemption on principle — a PR that adds any of
# these specs should delete its line in the same commit.
UNTESTED_DETECTORS = [
  "clojure/cli",
  "cpp/cli",
  "crystal/cli",
  "csharp/cli",
  "dart/cli",
  "dart/shelf",
  "elixir/bandit",
  "elixir/cli",
  "go/cli",
  "go/connect_rpc",
  "go/gf",
  "go/go_restful",
  "go/goyave",
  "go/hertz",
  "go/huma",
  "go/pocketbase",
  "groovy/cli",
  "haskell/cli",
  "java/cli",
  "java/dropwizard",
  "java/javalin",
  "java/jaxrs",
  "java/micronaut",
  "java/quarkus",
  "java/spark",
  "javascript/adonisjs",
  "javascript/astro",
  "javascript/cli",
  "javascript/fresh",
  "javascript/hapi",
  "javascript/nuxtjs",
  "javascript/remix",
  "javascript/sveltekit",
  "kotlin/cli",
  "kotlin/http4k",
  "lua/cli",
  "mobile/android",
  "mobile/well_known",
  "perl/cli",
  "php/cakephp",
  "php/cli",
  "php/thinkphp",
  "python/bottle",
  "python/cli",
  "python/quart",
  "python/robyn",
  "ruby/cli",
  "rust/actix_web",
  "rust/cli",
  "scala/cli",
  "scala/http4s",
  "specification/har",
  "specification/odata",
  "specification/typespec",
  "swift/cli",
  "swift/hummingbird",
  "swift/kitura",
  "typescript/trpc",
  "zig/cli",
  "zig/http",
  "zig/httpz",
  "zig/jetzig",
  "zig/tokamak",
  "zig/zap",
]

describe "detector spec coverage" do
  it "gives every registered detector a unit spec" do
    missing = detector_paths.reject do |detector|
      File.exists?(spec_path_for(detector)) || UNTESTED_DETECTORS.includes?(detector)
    end

    fail <<-MSG unless missing.empty?
      these detectors have no unit spec. A detector is the gate in front of an
      analyzer: when it is wrong the analyzer never runs and the scan reports an
      absence rather than an error, so it cannot ship untested. Add
      `spec/unit_test/detector/<language>/<framework>_spec.cr` for each:
        #{missing.join("\n  ")}
      MSG
  end

  # A stale entry silently re-exempts a detector that now has a spec, so the
  # allowlist can never shrink on its own.
  it "keeps the allowlist free of detectors that now have specs" do
    fixed = UNTESTED_DETECTORS.select { |detector| File.exists?(spec_path_for(detector)) }

    fail <<-MSG unless fixed.empty?
      these detectors now have unit specs — delete them from
      UNTESTED_DETECTORS: #{fixed.sort}
      MSG
  end

  it "keeps the allowlist free of detectors that no longer exist" do
    known = detector_paths.to_set
    gone = UNTESTED_DETECTORS.reject { |detector| known.includes?(detector) }

    fail <<-MSG unless gone.empty?
      UNTESTED_DETECTORS names detectors that are not in
      src/detector/detectors: #{gone.sort}
      MSG
  end

  # One naming convention, enforced. AGENTS.md documented
  # `{framework}_detector_spec.cr` while 149 of 177 specs used
  # `{framework}_spec.cr` — the doc described the minority. The 28 outliers were
  # renamed; this keeps the form from re-splitting, which matters because the
  # coverage check above resolves exactly one path per detector.
  it "uses one spec filename convention" do
    offenders = Dir.glob("spec/unit_test/detector/**/*_detector_spec.cr").sort

    fail <<-MSG unless offenders.empty?
      detector specs are named `{framework}_spec.cr` — the directory already
      says they are detector specs. Offenders:
        #{offenders.join("\n  ")}
      MSG
  end

  # Guards the guard: a broken glob would make every example above pass
  # vacuously.
  it "finds every registered detector" do
    detector_paths.size.should eq 244
  end
end
