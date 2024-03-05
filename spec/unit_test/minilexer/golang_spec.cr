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

describe "tokenize" do
  lexer = GolangLexer.new

  it "simple" do
    output = lexer.tokenize("
      users := rg.Group(\"/users\")

      users.GET(\"/\", func(c *gin.Context) {
        c.JSON(http.StatusOK, \"users\")
      })
    ")
    output[0].type.should eq(:newline)
    output[1].type.should eq(:code)
    output[2].type.should eq(:string)
  end
end