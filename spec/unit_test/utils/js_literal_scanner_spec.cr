require "spec"
require "../../../src/utils/js_literal_scanner"

describe Noir::JSLiteralScanner do
  describe "extract_paren_content" do
    it "extracts simple content" do
      result = Noir::JSLiteralScanner.extract_paren_content("(hello)", 1)
      result = result.should_not be_nil
      result.content.should eq("hello")
      result.end_pos.should eq(6) # Position of closing paren
    end

    it "handles nested parentheses" do
      result = Noir::JSLiteralScanner.extract_paren_content("(hello(world))", 1)
      result = result.should_not be_nil
      result.content.should eq("hello(world)")
      result.end_pos.should eq(13)
    end

    it "ignores parentheses inside strings" do
      result = Noir::JSLiteralScanner.extract_paren_content("('hello(world)')", 1)
      result = result.should_not be_nil
      result.content.should eq("'hello(world)'")
      result.end_pos.should eq(15)
    end

    it "ignores parentheses inside comments" do
      # Comments are stripped from the extracted content
      result = Noir::JSLiteralScanner.extract_paren_content("(// (hello)\n)", 1)
      result = result.should_not be_nil
      result.content.should eq("\n")
      result.end_pos.should eq(12)
    end

    it "handles complex nested structures" do
      content = "({a: (1+2), b: \"(str)\"})"
      result = Noir::JSLiteralScanner.extract_paren_content(content, 1)
      result = result.should_not be_nil
      result.content.should eq("{a: (1+2), b: \"(str)\"}")
      result.end_pos.should eq(23)
    end

    it "returns what it found if parentheses are unbalanced" do
      # If end of string reached, it returns what was collected
      result = Noir::JSLiteralScanner.extract_paren_content("(unbalanced", 1)
      result = result.should_not be_nil
      result.content.should eq("unbalanced")
      result.end_pos.should eq(11)
    end
  end

  describe "find_matching_brace" do
    it "finds matching brace" do
      content = "{ code }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(7)
    end

    it "handles nested braces" do
      content = "{ { code } }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(11)
    end

    it "ignores braces in strings" do
      content = "{ \"}\" }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(6)
    end

    it "returns nil if not found" do
      content = "{ code"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should be_nil
    end
  end

  describe "find_matching_paren" do
    it "finds matching paren" do
      content = "( code )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(7)
    end

    it "handles nested parens" do
      content = "( ( code ) )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(11)
    end

    it "ignores parens in strings" do
      content = "( \")\" )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(6)
    end

    it "returns nil if not found" do
      content = "( code"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should be_nil
    end
  end

  describe "edge cases pinned across the linear-scan rewrite" do
    it "treats slash after identifier as division inside paren content" do
      result = Noir::JSLiteralScanner.extract_paren_content("(a / b / c)", 1)
      result = result.should_not be_nil
      result.content.should eq("a / b / c")
      result.end_pos.should eq(10)
    end

    it "skips regex with escaped slash and flags after an operator" do
      result = Noir::JSLiteralScanner.extract_paren_content("(x = /a\\/b/gi)", 1)
      result = result.should_not be_nil
      result.content.should eq("x = /a\\/b/gi")
      result.end_pos.should eq(13)
    end

    it "keeps the historical past-the-end position for unterminated strings" do
      result = Noir::JSLiteralScanner.extract_paren_content("('ab", 1)
      result = result.should_not be_nil
      result.content.should eq("'ab")
      result.end_pos.should eq(5)
    end

    it "matches braces across a keyword-context regex containing a brace" do
      idx = Noir::JSLiteralScanner.find_matching_brace("{ return /}/ }", 0)
      idx.should eq(13)
    end

    it "returns nil for a brace opened before an unterminated string" do
      idx = Noir::JSLiteralScanner.find_matching_brace("{ \"ab", 0)
      idx.should be_nil
    end
  end

  describe "non-ASCII content (char-index API)" do
    it "extracts paren content containing multi-byte chars" do
      result = Noir::JSLiteralScanner.extract_paren_content("(한글 'x(y)' z)", 1)
      result = result.should_not be_nil
      result.content.should eq("한글 'x(y)' z")
      result.end_pos.should eq(12)
    end

    it "finds matching brace past a multi-byte comment" do
      idx = Noir::JSLiteralScanner.find_matching_brace("{ // 주석 }\n}", 0)
      idx.should eq(10)
    end

    it "ignores parens inside strings holding emoji" do
      idx = Noir::JSLiteralScanner.find_matching_paren("(f(\"🎉)\") )", 0)
      idx.should eq(9)
    end
  end

  describe "regex_context?" do
    it "accepts operators that expect an expression" do
      ['(', '[', '{', ',', ':', ';', '=', '!', '&', '|', '?', '>'].each do |ch|
        Noir::JSLiteralScanner.regex_context?(ch, "").should be_true
      end
    end

    it "accepts keywords that expect an expression" do
      Noir::JSLiteralScanner.regex_context?('n', "return").should be_true
      Noir::JSLiteralScanner.regex_context?('f', "typeof").should be_true
    end

    it "rejects a value-producing tail" do
      Noir::JSLiteralScanner.regex_context?(')', "").should be_false
      Noir::JSLiteralScanner.regex_context?(']', "").should be_false
      Noir::JSLiteralScanner.regex_context?('x', "x").should be_false
      Noir::JSLiteralScanner.regex_context?('n', "login").should be_false
      Noir::JSLiteralScanner.regex_context?(nil, "").should be_false
    end

    it "matches whole words, not keyword suffixes" do
      # "login" ends with "in" — a suffix match would call `login / 2`
      # a regex and swallow the rest of the expression.
      Noir::JSLiteralScanner.regex_context?('n', "in").should be_true
      Noir::JSLiteralScanner.regex_context?('n', "login").should be_false
    end

    it "treats '/' after a JSX `<` or a postfix `++` / `--` as division" do
      Noir::JSLiteralScanner.regex_context?('<', "").should be_false
      Noir::JSLiteralScanner.regex_context?('+', "", '+').should be_false
      Noir::JSLiteralScanner.regex_context?('-', "", '-').should be_false
      Noir::JSLiteralScanner.regex_context?('+', "", ' ').should be_true
    end
  end

  describe "template_literal_end" do
    it "skips a template nested inside a substitution" do
      src = "`<ul>${items.map(i => `<li>${i}</li>`)}</ul>`;x"
      Noir::JSLiteralScanner.template_literal_end(src.chars, src.size, 0).should eq(src.index!(';'))
    end

    it "keeps an apostrophe or a `}` inside a nested template inert" do
      ["`${a.map(n => `it's ${n}`)}`;", "`${rows.map(r => `}`)}`;", "`${rows.map(r => `{${r.a}}`)}`;"].each do |src|
        Noir::JSLiteralScanner.template_literal_end(src.chars, src.size, 0).should eq(src.size - 1)
      end
    end
  end

  describe "template_literal_end with a regex in a substitution" do
    it "keeps a quote or brace inside the regex out of the substitution state" do
      ["/'/g, ''", %(/"/g, ""), "/{/g, ''", %(/\\${/, "")].each do |re|
        src = "`a${ x.replace(#{re}) }b`;x"
        Noir::JSLiteralScanner.template_literal_end(src.chars, src.size, 0).should eq(src.index!(";"))
      end
    end
  end

  describe "failed regex scans" do
    it "stay linear on one long line of '/' that never closes" do
      src = "{ var q=" + "a=/[x" * 200_000 + "\n}"
      elapsed = Time.measure do
        Noir::JSLiteralScanner.find_matching_brace(src, 0).should eq(src.size - 1)
        Noir::JSLiteralScanner.extract_paren_content("(" + src + ")", 1).should_not be_nil
      end
      elapsed.should be < 2.seconds
    end
  end

  describe "find_matching_brace" do
    it "is not desynced by nested templates, JSX closing tags or postfix division" do
      [
        "{ res.send(`${items.map(i => `<li>${i}</li>`)}`); }",
        "{ const el = <div>{name}</div>;\n }",
        "{ const half = i++ / 2;\n const s = 'x'; }",
      ].each do |src|
        Noir::JSLiteralScanner.find_matching_brace(src, 0).should eq(src.size - 1)
      end
    end
  end
end
