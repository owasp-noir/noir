require "../../spec_helper"
require "../../../src/utils/utils"

describe "regex_matches_with_timeout?" do
  it "matches a simple string within timeout" do
    regex = /abc/
    regex_matches_with_timeout?(regex, "abcdef", 100.milliseconds).should be_true
  end

  it "returns false if it does not match within timeout" do
    regex = /xyz/
    regex_matches_with_timeout?(regex, "abcdef", 100.milliseconds).should be_false
  end

  it "returns false on timeout with backtracking (ReDoS protection)" do
    # This regex is vulnerable to catastrophic backtracking
    regex = /(a+)+b/
    input = "a" * 30 + "!" # Will take a long time to fail match
    
    # We use a very short timeout to ensure it triggers
    start_time = Time.instant
    result = regex_matches_with_timeout?(regex, input, 10.milliseconds)
    elapsed = Time.instant - start_time
    
    result.should be_false
    elapsed.should be < 500.milliseconds # Should not take seconds
  end
end
