require "../../spec_helper"
require "../../../src/minilexers/swift_lexer"

describe Noir::SwiftLexer do
  it "keeps the masked buffer aligned with the source length and preserves newlines" do
    src = "let a = \"hello\";\n// comment\nlet b = 42\n"
    lex = Noir::SwiftLexer.new(src)
    lex.masked.size.should eq(src.size)
    lex.masked_source.count('\n').should eq(src.count('\n'))
    lex.masked_lines.size.should eq(src.lines.size)
  end

  describe "comments" do
    it "masks single line comments while keeping delimiters" do
      src = "let x = 1 // app.get(\"fake\") { }\nlet y = 2"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines[0].should start_with("let x = 1 //")
      lex.masked_lines[0].should_not contain("fake")
      lex.masked_lines[0].count('{').should eq(0)
      lex.masked_lines[0].count('}').should eq(0)
      lex.in_code?(src.index!("fake")).should be_false
      lex.in_code?(src.index!("let y")).should be_true
    end

    it "masks nested block comments across multiple lines" do
      src = <<-SWIFT
        /*
           outer comment
           /* nested { brace } */
           still comment {
        */
        let real = true
        SWIFT

      lex = Noir::SwiftLexer.new(src)
      lex.masked_source.should_not contain("outer")
      lex.masked_source.should_not contain("nested")
      lex.masked_source.count('{').should eq(0)
      lex.masked_source.count('}').should eq(0)
      lex.in_code?(src.index!("outer")).should be_false
      lex.in_code?(src.index!("nested")).should be_false
      lex.in_code?(src.index!("real")).should be_true
    end
  end

  describe "string literals" do
    it "masks regular string content but preserves quotes" do
      src = "app.get(\"users\", \":id\")"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_source.should eq("app.get(\"     \", \"   \")")
      lex.masked_source.size.should eq(src.size)
      lex.in_code?(src.index!("users")).should be_false
      lex.in_code?(src.index!("app.get")).should be_true
    end

    it "handles character escapes in regular strings without early termination" do
      src = "let s = \"hello \\\" { brace } \\\" world\"; ok();"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines[0].count('{').should eq(0)
      lex.masked_lines[0].count('}').should eq(0)
      lex.masked_lines[0].should contain("ok();")
      lex.in_code?(src.index!("brace")).should be_false
      lex.in_code?(src.index!("ok")).should be_true
    end

    it "keeps code inside string interpolation unmasked and balanced" do
      src = "let s = \"User: \\( { () -> String in return \"nested \\(id)\" }() )\"; done();"
      lex = Noir::SwiftLexer.new(src)
      # Braces inside the closure in interpolation must survive in masked
      lex.masked_lines[0].count('{').should eq(1)
      lex.masked_lines[0].count('}').should eq(1)
      lex.masked_lines[0].should contain("return")
      lex.in_code?(src.index!("User")).should be_false
      lex.in_code?(src.index!("return")).should be_true
      lex.in_code?(src.index!("nested")).should be_false
      lex.in_code?(src.index!("id")).should be_true
      lex.in_code?(src.index!("done")).should be_true
    end

    it "masks multiline triple-quoted strings" do
      src = <<-SWIFT
        let json = """
        {
            "route": "app.get(\\"fake\\")",
            "closing": "}"
        }
        """
        let after = 1
        SWIFT

      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines.size.should eq(src.lines.size)
      lex.masked_source.should_not contain("route")
      lex.masked_source.should_not contain("fake")
      lex.masked_source.count('{').should eq(0)
      lex.masked_source.count('}').should eq(0)
      lex.in_code?(src.index!("route")).should be_false
      lex.in_code?(src.index!("after")).should be_true
    end

    it "masks raw single-line strings with varying hash counts" do
      src = "let r1 = #\"app.get(\"fake1\") { }\"#; let r2 = ##\"app.get(\"fake2\") { }\"##; let fin = 1;"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines[0].should_not contain("fake1")
      lex.masked_lines[0].should_not contain("fake2")
      lex.masked_lines[0].count('{').should eq(0)
      lex.masked_lines[0].count('}').should eq(0)
      lex.in_code?(src.index!("fake1")).should be_false
      lex.in_code?(src.index!("fake2")).should be_false
      lex.in_code?(src.index!("fin")).should be_true
    end

    it "handles raw multiline strings and allows inner triple quotes" do
      src = <<-SWIFT
        let raw = #"""
        Here is a triple quote """ inside raw multiline
        {
            app.get("fake_raw_multi")
        }
        """#
        let done = true
        SWIFT

      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines.size.should eq(src.lines.size)
      lex.masked_source.should_not contain("fake_raw_multi")
      lex.masked_source.count('{').should eq(0)
      lex.masked_source.count('}').should eq(0)
      lex.in_code?(src.index!("fake_raw_multi")).should be_false
      lex.in_code?(src.index!("done")).should be_true
    end

    it "handles raw string interpolation with matching hash counts" do
      src = "let s = #\"Value: \\#( { 1 + 2 }() )\"#; finish();"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_lines[0].count('{').should eq(1)
      lex.masked_lines[0].count('}').should eq(1)
      lex.in_code?(src.index!("Value")).should be_false
      lex.in_code?(src.index!("1 + 2")).should be_true
      lex.in_code?(src.index!("finish")).should be_true
    end

    it "does not treat directives like #if or #selector as raw strings" do
      src = "#if DEBUG\nlet x = 1\n#endif"
      lex = Noir::SwiftLexer.new(src)
      lex.masked_source.should contain("#if DEBUG")
      lex.masked_source.should contain("#endif")
      lex.in_code?(src.index!("DEBUG")).should be_true
    end

    it "handles hostile 100k nested string interpolation linearly without stack overflow" do
      s = "\"\\(" * 100_000
      lex = Noir::SwiftLexer.new(s)
      lex.masked_source.size.should eq(s.size)
    end
  end

  describe "brace-heavy sample matching_delimiter" do
    it "matches balanced delimiters despite heavy hostile braces in strings and comments" do
      src = <<-SWIFT
        func test() {
            let a = " { } { { "
            let b = """
            } } } {
            """
            let c = #" { } "#
            /* { { } */
            if true {
                let d = "}"
            }
        }
        SWIFT

      lex = Noir::SwiftLexer.new(src)
      open_func = src.index!("{")
      open_func.should_not be_nil
      close_func = src.rindex!("}")
      lex.matching_delimiter(open_func.not_nil!).should eq(close_func)
    end
  end
end
