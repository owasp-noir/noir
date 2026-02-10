require "spec"
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
    output = lexer.tokenize <<-GO
      users := rg.Group("/users")

      users.GET("/", func(c *gin.Context) {
        c.JSON(http.StatusOK, "users")
      })
      GO
    output[0].type.should eq(:code)
    output[1].type.should eq(:assign)
    output[2].type.should eq(:code)
    output[3].type.should eq(:string)
    output[3].value.should eq("/users")
    output[4].type.should eq(:code)
    output[5].type.should eq(:newline)
    output[6].type.should eq(:newline)
    output[7].type.should eq(:code)
    output[8].type.should eq(:string)
    output[9].type.should eq(:code)
    output[10].type.should eq(:newline)
    output[11].type.should eq(:code)
    output[12].type.should eq(:string)
    output[13].type.should eq(:code)
    output[14].type.should eq(:newline)
    output[15].type.should eq(:code)
  end
end
