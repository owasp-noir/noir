require "../../../src/minilexers/golang"

describe "initialize" do
  lexer = GolangLexer.new

  it "init" do
    lexer.class.should eq(GolangLexer)
  end

  it "default mode" do
    lexer.mode.should eq(:normal)
  end

  it "persistent mode" do
    lexer.mode = :persistent
    lexer.mode.should eq(:persistent)
  end
end
