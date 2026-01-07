require "../../../spec_helper"
require "../../../../src/models/minilexer/token.cr"

describe "Token" do
  describe "initialization with 3 arguments" do
    it "creates token with type, value, and index" do
      token = Token.new(:string, "hello", 0)

      token.type.should eq(:string)
      token.value.should eq("hello")
      token.index.should eq(0)
      token.position.should eq(0)
      token.line.should eq(0)
    end
  end

  describe "initialization with 5 arguments" do
    it "creates token with all properties" do
      token = Token.new(:identifier, "test", 1, 10, 5)

      token.type.should eq(:identifier)
      token.value.should eq("test")
      token.index.should eq(1)
      token.position.should eq(10)
      token.line.should eq(5)
    end
  end

  describe "is?" do
    it "checks token type correctly" do
      token = Token.new(:keyword, "if", 0)

      token.is?(:keyword).should be_true
      token.is?(:string).should be_false
    end
  end

  describe "to_s" do
    it "formats normal tokens" do
      token = Token.new(:number, "42", 0)
      str = token.to_s

      str.should contain("number")
      str.should contain("42")
    end

    it "escapes newline in output" do
      token = Token.new(:newline, "\n", 0)
      str = token.to_s

      str.should contain("\\n")
      str.should_not contain("\n")
    end

    it "escapes tab in output" do
      token = Token.new(:tab, "\t", 0)
      str = token.to_s

      str.should contain("\\t")
      str.should_not contain("\t")
    end
  end

  describe "property setters" do
    it "allows setting type" do
      token = Token.new(:string, "test", 0)
      token.type = :identifier

      token.type.should eq(:identifier)
    end

    it "allows setting value" do
      token = Token.new(:string, "test", 0)
      token.value = "modified"

      token.value.should eq("modified")
    end

    it "allows setting position" do
      token = Token.new(:string, "test", 0)
      token.position = 100

      token.position.should eq(100)
    end

    it "allows setting line" do
      token = Token.new(:string, "test", 0)
      token.line = 42

      token.line.should eq(42)
    end
  end
end
