require "../spec_helper"

# Every example under spec/functional_test/testers/ must carry the `functional`
# tag, and this spec is the ratchet that keeps it true.
#
# `bin/noir_spec` holds both suites, and CI splits it into a
# `--tag functional` process and a `--tag '~functional'` one so they run in
# parallel. An untagged example in a tester file does not fail anything: it
# just silently joins the unit half, where it drags a full fixture scan along
# with it. So the split quietly stops being a split, and the only symptom is
# the unit half getting slower for no visible reason.
#
# `FunctionalTester` tags what it registers itself. What it cannot reach are the
# hand-written `describe` and `it` blocks a tester file adds around it, which is
# what this checks. Only top-level blocks are checked, because Crystal merges a
# parent's tags into its children (`Spec::Item#all_tags`), so a nested block
# inherits from the one that encloses it.
#
# This reads the spec sources rather than the registered example tree because
# `Spec::RootContext` exposes no public way to walk it. The glob is relative, so
# like the functional testers themselves this expects to run from the repository
# root.
TOP_LEVEL_BLOCK = /^(?:describe|context|it)[\s(]/

describe "functional tester tagging" do
  it "tags every top-level block in spec/functional_test/testers" do
    files = Dir.glob("spec/functional_test/testers/**/*.cr").sort
    files.should_not be_empty

    untagged = [] of String
    files.each do |path|
      File.read_lines(path).each_with_index do |line, index|
        next unless line.matches?(TOP_LEVEL_BLOCK)
        # Both halves matter: `tags:` alone would accept `tags: "slow"`, which
        # lands the block in the unit half just as an absent tag does.
        next if line.includes?("tags:") && line.includes?("functional")
        untagged << "#{path}:#{index + 1}: #{line}"
      end
    end

    unless untagged.empty?
      fail "top-level spec blocks missing `tags: \"functional\"`:\n#{untagged.join("\n")}"
    end
  end
end
