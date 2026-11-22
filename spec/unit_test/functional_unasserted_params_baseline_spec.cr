require "../spec_helper"

# `spec/functional_test/unasserted_params_baseline.txt` exempts addresses from
# `FunctionalTester`'s exactness check (see `check_unasserted_params` in
# `spec/functional_test/func_spec.cr`). The functional suite fails an entry
# that has gone stale; what it cannot see is an entry whose fixture or tester
# no longer exists, because no example ever looks that entry up. This spec
# covers that half, and keeps the file in a shape that diffs line by line.
#
# The file is a ratchet: entries may be deleted, never added. A new tester
# declares every param its fixture emits.

BASELINE_FILE = "spec/functional_test/unasserted_params_baseline.txt"

private def baseline_entries : Array(String)
  File.read_lines(BASELINE_FILE).reject { |line| line.empty? || line.starts_with?('#') }
end

describe "unasserted params baseline" do
  it "has one `<fixture path>\\t<METHOD>::<url>` per line" do
    baseline_entries.reject(&.matches?(/\Afixtures\/[^\t]+\t[^\t:]+::[^\t]+\z/)).should be_empty
  end

  it "is sorted and free of duplicates" do
    entries = baseline_entries
    entries.should eq entries.uniq.sort!
  end

  it "only names fixture paths that exist" do
    missing = baseline_entries.map(&.split('\t').first).uniq!.reject do |path|
      Dir.exists?(File.join("spec/functional_test", path))
    end
    missing.should be_empty
  end
end
