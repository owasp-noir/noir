require "../../spec_helper"
require "../../../src/minilexers/php_lexer"

describe Noir::PhpLexer do
  it "keeps the masked buffer aligned with the source length" do
    src = "Route::get('a'); /* x */ $y = <<<EOT\nhi\nEOT;\n"
    lex = Noir::PhpLexer.new(src)
    lex.masked.size.should eq(src.size)
  end

  describe "#matching_delimiter" do
    it "matches a closing brace, ignoring braces inside strings and comments" do
      src = %(function () { $a = "}"; /* } */ $b = 1; })
      lex = Noir::PhpLexer.new(src)
      open = src.index!('{')
      lex.matching_delimiter(open).should eq(src.rindex!('}'))
    end

    it "ignores braces, semicolons and quotes inside a heredoc body" do
      src = <<-PHP
        function () {
          $sql = <<<SQL
            { "quote'd"; } not real code
          SQL;
          return 1;
        }
        PHP
      lex = Noir::PhpLexer.new(src)
      open = src.index!('{')
      lex.matching_delimiter(open).should eq(src.rindex!('}'))
    end

    it "matches parentheses across nested calls" do
      src = %(group(function () { get("/x", fn($r) => 1); }))
      lex = Noir::PhpLexer.new(src)
      open = src.index!('(')
      lex.matching_delimiter(open).should eq(src.size - 1)
    end
  end

  describe "#statement_end" do
    it "ends at the top-level semicolon past nested parens and strings" do
      src = %(Route::get("/x;y", [A::class, "m;n"]); next();)
      lex = Noir::PhpLexer.new(src)
      stop = lex.statement_end(0)
      src[stop - 1].should eq(';')
      src[0...stop].should eq(%(Route::get("/x;y", [A::class, "m;n"]);))
    end

    it "treats the semicolon after a heredoc terminator as the statement end" do
      src = "$x = <<<EOT\n a; b; {}\nEOT;\nnext();"
      lex = Noir::PhpLexer.new(src)
      stop = lex.statement_end(0)
      src[0...stop].should end_with("EOT;")
    end
  end

  describe "#in_code? / #skip_ranges" do
    it "masks single/double strings, line and block comments" do
      src = <<-PHP
        $a = 'Route::get("/s")';
        // Route::get("/c")
        /* Route::get("/b") */
        Route::get("/real");
        PHP
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("/s")).should be_false
      lex.in_code?(src.index!("/c")).should be_false
      lex.in_code?(src.index!("/b")).should be_false
      # The trailing `;` of the real, unmasked call is code.
      lex.in_code?(src.rindex!(';')).should be_true
    end

    it "masks heredoc and nowdoc bodies" do
      src = "$h = <<<EOT\nRoute::get('/hd')\nEOT;\n$n = <<<'EON'\nRoute::get('/nd')\nEON;\n"
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("/hd")).should be_false
      lex.in_code?(src.index!("/nd")).should be_false
    end

    it "treats a PHP 8 attribute as code, not a # comment" do
      src = "#[Route('/p', methods: ['GET'])]\nfunction h() {}\n# real comment\n"
      lex = Noir::PhpLexer.new(src)
      # `methods` is a bareword inside the attribute -> code.
      lex.in_code?(src.index!("methods")).should be_true
      # a genuine `#` line comment is masked.
      lex.in_code?(src.index!("real comment")).should be_false
    end
  end

  describe "masking edge cases" do
    it "does not let `/*/` self-close the block comment" do
      # `/*/` is an OPEN comment, not a complete one — the route inside must
      # stay masked rather than leaking as code after a phantom close.
      src = "/*/ Route::get('/leak') */ ok();"
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("Route")).should be_false
      lex.in_code?(src.index!("ok")).should be_true
    end

    it "masks heredoc bodies under LF, CRLF and bare-CR line endings" do
      {"\n", "\r\n", "\r"}.each do |nl|
        src = "$h = <<<EOT#{nl}Route::get('/x')#{nl}EOT;#{nl}done();"
        lex = Noir::PhpLexer.new(src)
        lex.masked.size.should eq(src.size)
        lex.in_code?(src.index!("Route::get")).should be_false
        lex.in_code?(src.index!("done")).should be_true
      end
    end

    it "does not treat a digit-leading `<<<` label as a heredoc" do
      src = "$x = 1 <<<3;"
      lex = Noir::PhpLexer.new(src)
      lex.skip_ranges.should eq([] of Range(Int32, Int32))
    end
  end

  describe "#tokens" do
    it "produces a structural stream with operators, idents and string spans" do
      src = %(Route::get('/x')->name('home');)
      kinds = Noir::PhpLexer.new(src).tokens.map(&.kind)
      kinds.should eq([
        :ident, :double_colon, :ident, :lparen, :string, :rparen,
        :arrow, :ident, :lparen, :string, :rparen, :semicolon,
      ])
    end

    it "records line numbers and string values" do
      src = "a();\nRoute::post('/y');"
      str = Noir::PhpLexer.new(src).tokens.find! { |t| t.kind == :string }
      str.value.should eq("'/y'")
      str.line.should eq(2)
    end

    it "tokenizes variables, => and array brackets in a closure" do
      src = %(fn($r) => [$r => 1];)
      kinds = Noir::PhpLexer.new(src).tokens.map(&.kind)
      kinds.should eq([
        :ident, :lparen, :variable, :rparen, :double_arrow,
        :lbracket, :variable, :double_arrow, :rbracket, :semicolon,
      ])
    end

    it "emits comment and heredoc span tokens with correct kinds" do
      src = "/* c */ $x = <<<EOT\nbody\nEOT;\n"
      kinds = Noir::PhpLexer.new(src).tokens.map(&.kind)
      kinds.should contain(:comment)
      kinds.should contain(:heredoc)
      kinds.should contain(:variable)
    end

    it "returns no tokens for empty source and skips a lone $" do
      Noir::PhpLexer.new("").tokens.should be_empty
      Noir::PhpLexer.new("$ ").tokens.should be_empty
    end

    it "numbers token lines under bare-CR and CRLF endings" do
      cr = Noir::PhpLexer.new("a();\rb();\rc();").tokens
      cr.find! { |t| t.value == "b" }.line.should eq(2)
      cr.find! { |t| t.value == "c" }.line.should eq(3)
      crlf = Noir::PhpLexer.new("a();\r\nb();").tokens
      crlf.find! { |t| t.value == "b" }.line.should eq(2)
    end
  end
end
