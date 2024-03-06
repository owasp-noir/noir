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
    output[2].type.should eq(:assign)
    output[3].type.should eq(:code)
    output[4].type.should eq(:string)
    output[4].value.should eq("/users")
    output[5].type.should eq(:code)
    output[6].type.should eq(:newline)
    output[7].type.should eq(:newline)
    output[8].type.should eq(:code)
    output[9].type.should eq(:string)
    output[10].type.should eq(:code)
    output[11].type.should eq(:newline)
    output[12].type.should eq(:code)
    output[13].type.should eq(:string)
    output[14].type.should eq(:code)
    output[15].type.should eq(:newline)
    output[16].type.should eq(:code)
    output[17].type.should eq(:newline)
  end
end
