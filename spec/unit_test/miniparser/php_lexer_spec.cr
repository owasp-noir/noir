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
  end
end
