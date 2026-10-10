require "spec"
require "../../../src/utils/call_fold"

private def cut_hash_comment(line : String) : String
  (i = line.index('#')) ? line[0, i] : line
end

describe Noir::CallFold do
  it "folds a wrapped call or subscript onto its opening line" do
    lines = [
      "  params.fetch(  # why (not",
      "    :q",
      "  )",
      "  env.params.query[",
      "    \"k\"",
      "  ]",
      "  f(a",
      "    and b)",
    ]
    Noir::CallFold.fold(lines) { |l| cut_hash_comment(l) }.should eq([
      "  params.fetch(:q)", "    :q", "  )",
      "  env.params.query[\"k\"]", "    \"k\"", "  ]",
      "  f(a and b)", "    and b)",
    ])
  end

  it "leaves comments, strings and long calls unfolded" do
    lines = ["  # params.fetch(", "  #   :ghost)", "  x = \"(\" + y", "  z"]
    Noir::CallFold.fold(lines) { |l| cut_hash_comment(l) }.should eq(["", "", "  x = \"(\" + y", "  z"])

    long = ["call("] + Array.new(Noir::CallFold::MAX_CONTINUATION_LINES + 1) { |i| "a#{i}," } + [")"]
    Noir::CallFold.fold(long) { |l| l }.should eq(long)
  end
end
