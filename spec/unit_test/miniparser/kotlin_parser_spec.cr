require "spec"
require "../../../src/miniparsers/kotlin"

describe KotlinParser do
  describe "get_package_name" do
    it "extracts package name from tokens" do
      lexer = KotlinLexer.new
      tokens = lexer.tokenize("package com.example.app\nclass Foo {}")
      parser = KotlinParser.new("/src/com/example/app/Foo.kt", tokens)
      package = parser.get_package_name(parser.tokens)
      package.should eq("com.example.app")
    end

    it "returns empty string when no package declaration" do
      lexer = KotlinLexer.new
      tokens = lexer.tokenize("class Foo {}")
      parser = KotlinParser.new("/Foo.kt", tokens)
      package = parser.get_package_name(parser.tokens)
      package.should eq("")
    end
  end

  describe "get_root_source_directory" do
    it "resolves root directory based on package depth" do
      lexer = KotlinLexer.new
      tokens = lexer.tokenize("class Foo {}")
      parser = KotlinParser.new("/src/Foo.kt", tokens)
      root = parser.get_root_source_directory("/src/com/example/Foo.kt", "com.example")
      root.should eq(Path.new("/src"))
    end
  end

  describe "parse_import_statements" do
    it "parses simple import statements" do
      code = <<-KOTLIN
      package com.example
      import kotlin.collections.List
      import kotlin.collections.Map
      class Foo {}
      KOTLIN

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)
      parser.import_statements.should contain("kotlin.collections.List")
      parser.import_statements.should contain("kotlin.collections.Map")
    end

    it "parses wildcard import" do
      code = <<-KOTLIN
      import kotlin.collections.*
      class Foo {}
      KOTLIN

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)
      parser.import_statements.should contain("kotlin.collections.*")
    end
  end

  describe "parse_classes" do
    it "parses a single class" do
      code = "package com.example\nclass MyClass {\nfun hello() {}\n}"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/MyClass.kt", tokens)
      parser.classes.size.should eq(1)
      parser.classes[0].name.should eq("MyClass")
    end

    it "parses class without body" do
      code = "package com.example\nclass EmptyClass"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/EmptyClass.kt", tokens)
      parser.classes.size.should eq(1)
      parser.classes[0].name.should eq("EmptyClass")
    end

    it "parses data class" do
      code = "package com.example\ndata class User(val name: String, val age: Int)"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/User.kt", tokens)
      parser.classes.size.should eq(1)
      parser.classes[0].name.should eq("User")
    end
  end

  describe "parse_methods" do
    it "extracts methods from class" do
      code = "package com.example\nclass Foo {\nfun doSomething() {}\nfun getName(): String { return \"\" }\n}"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)
      parser.classes.size.should eq(1)
      methods = parser.classes[0].methods
      methods.has_key?("doSomething").should be_true
      methods.has_key?("getName").should be_true
    end
  end

  describe "parse_class_parameters" do
    it "extracts primary constructor val parameters" do
      code = "package com.example\ndata class User(val name: String, val age: Int)"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/User.kt", tokens)
      parser.classes.size.should be >= 1
      fields = parser.classes[0].fields
      fields.has_key?("name").should be_true
      fields["name"].type.should eq("String")
      fields["name"].val_or_var.should eq("val")
      fields.has_key?("age").should be_true
      fields["age"].type.should eq("Int")
    end

    it "extracts var parameters as mutable" do
      code = "package com.example\nclass Config(var host: String, var port: Int)"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Config.kt", tokens)
      parser.classes.size.should be >= 1
      fields = parser.classes[0].fields
      fields.has_key?("host").should be_true
      fields["host"].val_or_var.should eq("var")
      fields["host"].has_setter?.should be_true
    end
  end

  describe "find_bracket_partner" do
    it "finds matching closing bracket" do
      code = "package com.example\nclass Foo {\nfun bar() {}\n}"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)

      # Find the first LCURL
      lcurl_index = parser.tokens.index { |t| t.type == :LCURL }
      lcurl_index.should_not be_nil
      if lcurl_index
        partner = parser.find_bracket_partner(lcurl_index)
        partner.should_not be_nil
        if partner
          parser.tokens[partner].type.should eq(:RCURL)
        end
      end
    end

    it "returns nil for non-bracket token" do
      code = "package com.example\nclass Foo {}"

      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)

      # IDENTIFIER token should return nil
      id_index = parser.tokens.index { |t| t.type == :IDENTIFIER }
      if id_index
        partner = parser.find_bracket_partner(id_index)
        partner.should be_nil
      end
    end
  end

  describe "modifier?" do
    it "recognizes Kotlin modifiers" do
      code = "class Foo {}"
      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)

      # NEWLINE is treated as a modifier (returns true)
      newline_token = Token.new(:NEWLINE, "\n", 0)
      parser.modifier?(newline_token).should be_true

      # Known modifier keyword
      open_token = Token.new(:IDENTIFIER, "open", 0)
      parser.modifier?(open_token).should be_true

      data_token = Token.new(:IDENTIFIER, "data", 0)
      parser.modifier?(data_token).should be_true
    end

    it "returns false for non-modifier tokens" do
      code = "class Foo {}"
      lexer = KotlinLexer.new
      tokens = lexer.tokenize(code)
      parser = KotlinParser.new("/Foo.kt", tokens)

      random_token = Token.new(:IDENTIFIER, "someVariable", 0)
      parser.modifier?(random_token).should be_false
    end
  end

  describe "KotlinParser::FieldModel" do
    it "val field has getter but no setter" do
      field = KotlinParser::FieldModel.new("public", "val", "String", "name", "")
      field.has_getter?.should be_true
      field.has_setter?.should be_false
    end

    it "var field has both getter and setter" do
      field = KotlinParser::FieldModel.new("public", "var", "String", "name", "")
      field.has_getter?.should be_true
      field.has_setter?.should be_true
    end
  end
end
