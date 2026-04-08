require "spec"
require "../../../src/miniparsers/python"

describe PythonParser do
  describe "parse_global_variables" do
    it "extracts typed global variable" do
      code = <<-PYTHON
      BASE_URL: str = "http://localhost"
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", tokens, parsers)
      parser.@global_variables.has_key?("BASE_URL").should be_true
      parser.@global_variables["BASE_URL"].value.should eq("http://localhost")
    end

    it "extracts untyped string variable" do
      code = <<-PYTHON
      name = "hello"
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", tokens, parsers)
      parser.@global_variables.has_key?("name").should be_true
      parser.@global_variables["name"].type.should eq("str")
      parser.@global_variables["name"].value.should eq("hello")
    end

    it "extracts multiple global variables" do
      code = <<-PYTHON
      host = "localhost"
      port = 8080
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/config.py", tokens, parsers)
      parser.@global_variables.has_key?("host").should be_true
      parser.@global_variables.has_key?("port").should be_true
    end
  end

  describe "normalize" do
    it "normalizes a simple string token" do
      code = <<-PYTHON
      x = "hello world"
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", tokens, parsers)

      # Find the STRING token
      string_idx = tokens.index { |t| t.type == :STRING }
      if string_idx
        result = parser.normalize(string_idx)
        result.should eq("hello world")
      end
    end
  end

  describe "extract_assign_data" do
    it "extracts string assignment" do
      code = <<-PYTHON
      x = "test_value"
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", tokens, parsers)

      # Find the ASSIGN token, the value is the next token
      assign_idx = tokens.index { |t| t.type == :ASSIGN }
      if assign_idx
        result = parser.extract_assign_data(assign_idx + 1)
        result[0].should eq("str")
        result[1].should eq("test_value")
      end
    end

    it "extracts numeric assignment as raw data" do
      code = <<-PYTHON
      count = 42
      PYTHON

      lexer = PythonLexer.new
      tokens = lexer.tokenize(code)
      parsers = Hash(String, PythonParser).new
      parser = PythonParser.new("/app.py", tokens, parsers)

      assign_idx = tokens.index { |t| t.type == :ASSIGN }
      if assign_idx
        result = parser.extract_assign_data(assign_idx + 1)
        result[1].should eq("42")
      end
    end
  end

  describe "PythonParser::GlobalVariables" do
    it "to_s with type" do
      gv = PythonParser::GlobalVariables.new("host", "str", "localhost", "/app.py")
      gv.to_s.should contain("host")
      gv.to_s.should contain("str")
      gv.to_s.should contain("localhost")
    end

    it "to_s without type" do
      gv = PythonParser::GlobalVariables.new("count", nil, "42", "/app.py")
      gv.to_s.should contain("count")
      gv.to_s.should contain("42")
    end
  end

  describe "PythonParser::ImportModel" do
    it "to_s with path" do
      im = PythonParser::ImportModel.new("os", "/usr/lib/python3/os.py", nil)
      im.to_s.should contain("os")
      im.to_s.should contain("/usr/lib/python3/os.py")
    end

    it "to_s without path" do
      im = PythonParser::ImportModel.new("os", nil, nil)
      im.to_s.should contain("os")
      im.to_s.should contain("unknown")
    end

    it "to_s with alias" do
      im = PythonParser::ImportModel.new("numpy", "/site-packages/numpy.py", "np")
      im.to_s.should contain("numpy")
      im.to_s.should contain("np")
    end
  end
end
