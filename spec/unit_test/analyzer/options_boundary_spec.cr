require "../../spec_helper"
require "../../../src/models/analyzer"

# `Analyzer#callees_needed?` (src/models/analyzer.cr) has existed, with a doc
# comment telling analyzers to use it, for as long as the callee flags have.
# Sixty-five analyzers re-implemented its body inline anyway:
#
#     include_callee = any_to_bool(@options["include_callee"]?) ||
#                      any_to_bool(@options["ai_context"]?)
#
# Two of them went further and declared a `private def callees_needed?` whose
# body — and doc comment — duplicated the base method verbatim.
#
# Nothing failed when they drifted, because nothing checked. The cost is not
# the duplication itself but the coupling it encodes: every one of those
# lines is an analyzer reaching past its base class into the raw options
# hash, so the set of keys the analyzer layer depends on could only be
# discovered by grep. That set is now four keys wide and shrinking.
#
# Repo-relative glob: `crystal spec` runs from the repository root (same
# assumption as spec/unit_test/detector/applicable_lookup_fidelity_spec.cr).
private def analyzer_sources : Array(String)
  Dir.glob("src/analyzer/**/*.cr").sort
end

private def offending_lines(pattern : Regex) : Array(String)
  analyzer_sources.flat_map do |file|
    File.read_lines(file).each_with_index.compact_map do |line, index|
      "#{file}:#{index + 1}: #{line.strip}" if line.matches?(pattern)
    end
  end
end

describe "analyzer options boundary" do
  it "reads the callee flags only through callees_needed?" do
    offenders = offending_lines(/@options\[\s*"(?:include_callee|ai_context)"\s*\]/)

    fail <<-MSG unless offenders.empty?
      analyzers must call `callees_needed?` instead of reading the callee
      flags out of the options hash. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  it "does not shadow callees_needed? with a local copy" do
    offenders = offending_lines(/^\s*(?:private\s+|protected\s+)?def\s+callees_needed\?/)

    fail <<-MSG unless offenders.empty?
      `callees_needed?` is defined once, on `Analyzer`. A subclass copy is a
      silent fork of the flag semantics. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  it "reads the worker count only through the base accessors" do
    offenders = offending_lines(/@(?:raw_)?options\[\s*"concurrency"\s*\]/)

    fail <<-MSG unless offenders.empty?
      analyzers must call `worker_count` / `bounded_worker_count` instead of
      reading `concurrency` out of the options hash. Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # The general rule the three specific ones above are instances of. The
  # ivar was renamed `@raw_options` in the base so every pre-existing
  # reach-through became a compile error — this keeps new ones from
  # appearing under either spelling.
  it "does not index the options hash anywhere under src/analyzer" do
    offenders = offending_lines(/@(?:raw_)?options\[/)

    fail <<-MSG unless offenders.empty?
      analyzers read options through accessors on `Analyzer`
      (`callees_needed?`, `worker_count`, `option_flag?`), never by
      indexing the hash. Add an accessor rather than a fourth spelling.
      Offending lines:
        #{offenders.join("\n  ")}
      MSG
  end

  # Guards the guard: a typo in the globs above would make both examples pass
  # vacuously, which is the failure mode that makes source-scanning specs
  # worthless.
  it "scans a non-trivial number of analyzer sources" do
    analyzer_sources.size.should be > 200
    analyzer_sources.count { |f| File.read(f).includes?("callees_needed?") }.should be > 50
  end
end

# `concurrency` was the last option key the analyzer layer read directly, at
# 21 sites all spelling it `@options["concurrency"].to_s.to_i`.
#
# `worker_count` / `bounded_worker_count` are protected, so reach them the
# way a subclass would.
private class WorkerCountProbe < Analyzer
  def visible_worker_count : Int32
    worker_count
  end

  def visible_bounded_worker_count : Int32
    bounded_worker_count
  end
end

private def worker_probe(value : String?) : WorkerCountProbe
  options = create_test_options
  if value
    options["concurrency"] = YAML::Any.new(value)
  else
    options.delete("concurrency")
  end
  WorkerCountProbe.new(options)
end

describe "Analyzer worker count" do
  it "reads a configured worker count" do
    worker_probe("8").visible_worker_count.should eq 8
  end

  # Each of these used to raise or spawn zero workers. `0` was the worst:
  # the analyzer ran, spawned nothing, and reported no endpoints.
  it "floors at one worker instead of raising or spawning none" do
    worker_probe("0").visible_worker_count.should eq 1
    worker_probe("-4").visible_worker_count.should eq 1
    worker_probe("abc").visible_worker_count.should eq 1
    worker_probe(nil).visible_worker_count.should eq 1
  end

  it "caps the shared file walk at MAX_ANALYZER_WORKERS" do
    worker_probe("1000").visible_bounded_worker_count.should eq Analyzer::MAX_ANALYZER_WORKERS
    worker_probe("8").visible_bounded_worker_count.should eq 8
  end

  # The per-analyzer walks deliberately stay uncapped — see the comment on
  # `bounded_worker_count`. Folding them in would silently drop a
  # `--concurrency 100` run to 64.
  it "leaves the uncapped accessor uncapped" do
    worker_probe("1000").visible_worker_count.should eq 1000
  end
end
