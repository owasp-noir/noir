require "spec"
require "../../../src/utils/jvm_delimiter"

describe Noir::JvmDelimiter do
  it "returns character offsets past nested pairs, escaped quotes and character literals" do
    code = "한({\"}\", f(\"a\\\"}\", '}')})"
    open = code.index!('{')
    Noir::JvmDelimiter.find_matching_delimiter(code, open, '{', '}').should eq code.rindex!('}')
  end

  it "preserves the double-quote-only paren scan used by Spring and Javalin" do
    code = "f(\"a)\", ')', x)"
    Noir::JvmDelimiter.find_matching_paren(code, 1).should eq code.index!("')'") + 1
    Noir::JvmDelimiter.find_matching_delimiter(code, 1, '(', ')').should eq code.size - 1
  end

  it "leaves comment handling to the caller and returns nil when a pair never closes" do
    Noir::JvmDelimiter.find_matching_paren("(/* ) */)", 0).should eq 4
    Noir::JvmDelimiter.find_matching_paren("(\"unfinished)", 0).should be_nil
    Noir::JvmDelimiter.find_matching_paren("(", 0).should be_nil
  end
end
