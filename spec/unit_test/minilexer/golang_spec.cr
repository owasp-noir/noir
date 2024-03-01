require "../../../src/minilexers/golang"

describe "initialize" do
  lexer = GolangLexer.new

  it "init" do
    lexer.class.should eq(GolangLexer)
  end
end
