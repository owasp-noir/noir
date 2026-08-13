require "../../spec_helper"
require "../../../src/utils/utils"

describe "regex_matches_bounded?" do
  it "matches a simple string" do
    regex_matches_bounded?(/abc/, "abcdef").should be_true
  end

  it "returns false when the pattern does not match" do
    regex_matches_bounded?(/xyz/, "abcdef").should be_false
  end

  # The bound is PCRE2's match limit, which raises `Regex::Error` rather than
  # returning. Without the rescue this call propagates and ends the AI grep
  # walk on one pathological line, so assert both halves: the bare call really
  # does raise, and the helper really does absorb it.
  #
  # The pattern matters. The previous version of this spec used `/(a+)+b/` on
  # 30 `a`s, which PCRE2 auto-possessifies — it completes in 0.0ms, so the
  # example asserted `elapsed < 500ms` against something that could never be
  # slow and never exercised the guard at all. `(a|a)+$` defeats that
  # optimisation because the alternation branches are indistinguishable.
  describe "catastrophic backtracking" do
    catastrophic = Regex.new("(a|a)+$")
    subject = "a" * 26 + "!"

    it "raises out of a bare Regex#matches?" do
      expect_raises(Regex::Error) do
        catastrophic.matches?(subject)
      end
    end

    it "is absorbed into a false" do
      regex_matches_bounded?(catastrophic, subject).should be_false
    end
  end
end
