require "../../spec_helper"

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

  # Guards the guard: a typo in the globs above would make both examples pass
  # vacuously, which is the failure mode that makes source-scanning specs
  # worthless.
  it "scans a non-trivial number of analyzer sources" do
    analyzer_sources.size.should be > 200
    analyzer_sources.count { |f| File.read(f).includes?("callees_needed?") }.should be > 50
  end
end
