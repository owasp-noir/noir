require "../../spec_helper"
require "../../../src/utils/parser_limit"

describe "ParserLimit" do
  # Reset state before each test so ENV changes take effect.
  before_each { ParserLimit.reset }
  after_all { ENV.delete("NOIR_PARSER_MAX_DEPTH"); ParserLimit.reset }

  describe ".max_depth" do
    it "returns nil when NOIR_PARSER_MAX_DEPTH is not set" do
      ENV.delete("NOIR_PARSER_MAX_DEPTH")
      ParserLimit.max_depth.should be_nil
    end

    it "returns 0 when set to 0" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "0"
      ParserLimit.max_depth.should eq(0)
    end

    it "returns the integer value when set to a positive number" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "3"
      ParserLimit.max_depth.should eq(3)
    end

    it "returns nil when set to a negative number (no limit)" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "-1"
      ParserLimit.max_depth.should be_nil
    end

    it "returns nil when set to a non-integer string" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "abc"
      ParserLimit.max_depth.should be_nil
    end
  end

  describe ".allow_depth?" do
    it "returns true for any depth when NOIR_PARSER_MAX_DEPTH is not set" do
      ENV.delete("NOIR_PARSER_MAX_DEPTH")
      ParserLimit.allow_depth?(0).should be_true
      ParserLimit.allow_depth?(100).should be_true
    end

    it "returns false for depth 0 when max depth is 0 (entry file only)" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "0"
      ParserLimit.allow_depth?(0).should be_false
    end

    it "returns true for depth 0 and false for depth 1 when max depth is 1" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "1"
      ParserLimit.allow_depth?(0).should be_true
      ParserLimit.allow_depth?(1).should be_false
    end

    it "allows depths below max and blocks depths at or above max" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "3"
      ParserLimit.allow_depth?(0).should be_true
      ParserLimit.allow_depth?(1).should be_true
      ParserLimit.allow_depth?(2).should be_true
      ParserLimit.allow_depth?(3).should be_false
      ParserLimit.allow_depth?(4).should be_false
    end

    it "returns true for any depth when set to negative (no limit)" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "-5"
      ParserLimit.allow_depth?(0).should be_true
      ParserLimit.allow_depth?(999).should be_true
    end
  end

  describe ".reset" do
    it "allows re-reading the environment variable" do
      ENV["NOIR_PARSER_MAX_DEPTH"] = "2"
      ParserLimit.max_depth.should eq(2)

      ENV["NOIR_PARSER_MAX_DEPTH"] = "5"
      ParserLimit.reset
      ParserLimit.max_depth.should eq(5)
    end
  end
end
