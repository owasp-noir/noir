require "../../spec_helper"
require "../../../src/minilexers/php_lexer"

describe Noir::PhpLexer do
  it "keeps the masked buffer aligned with the source length" do
    src = "Route::get('a'); /* x */ $y = <<<EOT\nhi\nEOT;\n"
    lex = Noir::PhpLexer.new(src, php_mode: true)
    lex.masked.size.should eq(src.size)
  end

  describe "#matching_delimiter" do
    it "matches a closing brace, ignoring braces inside strings and comments" do
      src = %(function () { $a = "}"; /* } */ $b = 1; })
      lex = Noir::PhpLexer.new(src, php_mode: true)
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
      lex = Noir::PhpLexer.new(src, php_mode: true)
      open = src.index!('{')
      lex.matching_delimiter(open).should eq(src.rindex!('}'))
    end

    it "matches parentheses across nested calls" do
      src = %(group(function () { get("/x", fn($r) => 1); }))
      lex = Noir::PhpLexer.new(src, php_mode: true)
      open = src.index!('(')
      lex.matching_delimiter(open).should eq(src.size - 1)
    end
  end

  describe "#statement_end" do
    it "ends at the top-level semicolon past nested parens and strings" do
      src = %(Route::get("/x;y", [A::class, "m;n"]); next();)
      lex = Noir::PhpLexer.new(src, php_mode: true)
      stop = lex.statement_end(0)
      src[stop - 1].should eq(';')
      src[0...stop].should eq(%(Route::get("/x;y", [A::class, "m;n"]);))
    end

    it "treats the semicolon after a heredoc terminator as the statement end" do
      src = "$x = <<<EOT\n a; b; {}\nEOT;\nnext();"
      lex = Noir::PhpLexer.new(src, php_mode: true)
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
      lex = Noir::PhpLexer.new(src, php_mode: true)
      lex.in_code?(src.index!("/s")).should be_false
      lex.in_code?(src.index!("/c")).should be_false
      lex.in_code?(src.index!("/b")).should be_false
      # The trailing `;` of the real, unmasked call is code.
      lex.in_code?(src.rindex!(';')).should be_true
    end

    it "masks heredoc and nowdoc bodies" do
      src = "$h = <<<EOT\nRoute::get('/hd')\nEOT;\n$n = <<<'EON'\nRoute::get('/nd')\nEON;\n"
      lex = Noir::PhpLexer.new(src, php_mode: true)
      lex.in_code?(src.index!("/hd")).should be_false
      lex.in_code?(src.index!("/nd")).should be_false
    end

    it "treats a PHP 8 attribute as code, not a # comment" do
      src = "#[Route('/p', methods: ['GET'])]\nfunction h() {}\n# real comment\n"
      lex = Noir::PhpLexer.new(src, php_mode: true)
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
      lex = Noir::PhpLexer.new(src, php_mode: true)
      lex.in_code?(src.index!("Route")).should be_false
      lex.in_code?(src.index!("ok")).should be_true
    end

    it "masks heredoc bodies under LF, CRLF and bare-CR line endings" do
      {"\n", "\r\n", "\r"}.each do |nl|
        src = "$h = <<<EOT#{nl}Route::get('/x')#{nl}EOT;#{nl}done();"
        lex = Noir::PhpLexer.new(src, php_mode: true)
        lex.masked.size.should eq(src.size)
        lex.in_code?(src.index!("Route::get")).should be_false
        lex.in_code?(src.index!("done")).should be_true
      end
    end

    it "does not treat a digit-leading `<<<` label as a heredoc" do
      src = "$x = 1 <<<3;"
      lex = Noir::PhpLexer.new(src, php_mode: true)
      lex.skip_ranges.should eq([] of Range(Int32, Int32))
    end
  end

  describe "#tokens" do
    it "produces a structural stream with operators, idents and string spans" do
      src = %(Route::get('/x')->name('home');)
      kinds = Noir::PhpLexer.new(src, php_mode: true).tokens.map(&.kind)
      kinds.should eq([
        :ident, :double_colon, :ident, :lparen, :string, :rparen,
        :arrow, :ident, :lparen, :string, :rparen, :semicolon,
      ])
    end

    it "records line numbers and string values" do
      src = "a();\nRoute::post('/y');"
      str = Noir::PhpLexer.new(src, php_mode: true).tokens.find! { |t| t.kind == :string }
      str.value.should eq("'/y'")
      str.line.should eq(2)
    end

    it "tokenizes variables, => and array brackets in a closure" do
      src = %(fn($r) => [$r => 1];)
      kinds = Noir::PhpLexer.new(src, php_mode: true).tokens.map(&.kind)
      kinds.should eq([
        :ident, :lparen, :variable, :rparen, :double_arrow,
        :lbracket, :variable, :double_arrow, :rbracket, :semicolon,
      ])
    end

    it "emits comment and heredoc span tokens with correct kinds" do
      src = "/* c */ $x = <<<EOT\nbody\nEOT;\n"
      kinds = Noir::PhpLexer.new(src, php_mode: true).tokens.map(&.kind)
      kinds.should contain(:comment)
      kinds.should contain(:heredoc)
      kinds.should contain(:variable)
    end

    it "returns no tokens for empty source and skips a lone $" do
      Noir::PhpLexer.new("").tokens.should be_empty
      Noir::PhpLexer.new("$ ", php_mode: true).tokens.should be_empty
    end

    it "numbers token lines under bare-CR and CRLF endings" do
      cr = Noir::PhpLexer.new("a();\rb();\rc();", php_mode: true).tokens
      cr.find! { |t| t.value == "b" }.line.should eq(2)
      cr.find! { |t| t.value == "c" }.line.should eq(3)
      crlf = Noir::PhpLexer.new("a();\r\nb();", php_mode: true).tokens
      crlf.find! { |t| t.value == "b" }.line.should eq(2)
    end
  end

  # A `.php` file is HTML with islands of code in it. Everything outside
  # `<?php … ?>` is literal output: lexing it as code let one apostrophe in
  # prose open a string that masked the rest of the file, so every route
  # declared below it disappeared.
  describe "inline HTML mode" do
    it "does not let an apostrophe in leading HTML mask the code below it" do
      src = <<-PHP
        <h1>Today's report</h1>
        <?php
        Route::get('/one', 'C@a');
        Route::post('/two', 'C@b');
        PHP
      lex = Noir::PhpLexer.new(src)
      lex.masked.size.should eq(src.size)
      lex.in_code?(src.index!("Route::get")).should be_true
      lex.in_code?(src.index!("Route::post")).should be_true
      lex.tokens.map(&.value).should contain("Route")
      # The prose itself is inert, and it produces no token of its own.
      lex.in_code?(src.index!("Today")).should be_false
      lex.tokens.map(&.value).should_not contain("Today")
    end

    it "returns to HTML mode at `?>` and back to code at the next open tag" do
      src = <<-PHP
        <?php Route::get('/before', 'C@a'); ?>
        <p>Today's report</p>
        <?php Route::get('/after', 'C@b');
        PHP
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("/before")).should be_false # a string, still masked
      lex.in_code?(src.index!("'/after'")).should be_false
      lex.in_code?(src.index!("Route::get('/after'")).should be_true
      lex.in_code?(src.index!("report")).should be_false
      lex.tokens.count { |t| t.value == "Route" }.should eq(2)
    end

    it "opens code on the `<?=` short echo tag" do
      src = "<h1>it's here</h1>\n<?= route('/x') ?>\n<p>and's here</p>\n"
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("route")).should be_true
      lex.tokens.map(&.value).should contain("route")
      lex.tokens.map(&.value).should_not contain("h1")
    end

    it "keeps PHP mode when `?>` is written inside a string or a block comment" do
      src = <<-PHP
        <?php
        $close = '?>';
        /* ?> */
        Route::get('/still-code', 'C@a');
        PHP
      lex = Noir::PhpLexer.new(src)
      lex.in_code?(src.index!("Route::get")).should be_true
      lex.tokens.map(&.value).should contain("Route")
    end

    it "closes PHP mode when `?>` ends a one-line `//` or `#` comment" do
      {"//", "#"}.each do |marker|
        src = "<?php #{marker} note ?>\n<p>Today's report</p>\n<?php Route::get('/x', 'C@a');"
        lex = Noir::PhpLexer.new(src)
        lex.masked.size.should eq(src.size)
        lex.in_code?(src.index!("report")).should be_false
        lex.in_code?(src.index!("Route::get")).should be_true
      end
    end

    it "yields no tokens for a file that never opens PHP" do
      src = "<h1>Today's report</h1>\n<p>No code here; just { markup }.</p>\n"
      lex = Noir::PhpLexer.new(src)
      lex.masked.size.should eq(src.size)
      lex.tokens.should be_empty
      lex.in_code?(0).should be_false
      lex.masked.should_not contain('{')
    end

    it "does not open PHP on an XML processing instruction" do
      src = "<?xml version=\"1.0\"?>\n<note>it's inert</note>\n"
      Noir::PhpLexer.new(src).tokens.should be_empty
    end

    it "lexes to EOF when the final PHP block is never closed" do
      src = "<p>hi</p>\n<?php Route::get('/tail', 'C@a');"
      lex = Noir::PhpLexer.new(src)
      lex.masked.size.should eq(src.size)
      lex.in_code?(src.rindex!(';')).should be_true
    end

    it "preserves line numbers across a large HTML header" do
      header = Array.new(20) { |i| "<p>Line #{i + 1}: it's fine</p>" }.join("\n")
      src = "#{header}\n<?php\nRoute::get('/x', 'C@a');\n"
      lex = Noir::PhpLexer.new(src)
      lex.masked.size.should eq(src.size)
      # 20 header lines, `<?php` on 21, the route on 22.
      lex.tokens.find! { |t| t.value == "Route" }.line.should eq(22)
    end

    it "does not start a heredoc or a comment from markup outside PHP" do
      src = "<p>a << b <<<EOT and // and /* never closed</p>\n<?php Route::get('/y', 'C@a');\n"
      lex = Noir::PhpLexer.new(src)
      lex.masked.size.should eq(src.size)
      lex.in_code?(src.index!("Route::get")).should be_true
    end
  end
end
