require "../spec_helper"
require "../../src/diff_gate"

describe Noir::DiffGate do
  it "parses a comma list case-insensitively, dropping blanks and repeats" do
    Noir::DiffGate.parse(" Added,,auth-removed,added ").should eq(["added", "auth-removed"])
    Noir::DiffGate.parse("").should be_empty
  end

  it "names the values it does not know" do
    Noir::DiffGate.unknown(["added", "removd", "changed"]).should eq(["removd"])
  end

  it "needs taggers only for auth-removed" do
    Noir::DiffGate.needs_taggers?(["added", "changed"]).should be_false
    Noir::DiffGate.needs_taggers?(["auth-removed"]).should be_true
  end

  it "fires the requested categories that have findings" do
    counts = {"added" => 2, "removed" => 0, "changed" => 1, "auth-removed" => 0}
    Noir::DiffGate.fired(["added", "removed", "auth-removed"], counts).should eq(["added"])
    Noir::DiffGate.fired(["removed"], counts).should be_empty
  end
end
