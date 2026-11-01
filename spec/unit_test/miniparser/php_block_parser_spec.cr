require "../../spec_helper"
require "../../../src/miniparsers/php_block_parser"

private def kinds(parser : Noir::PhpBlockParser) : Array(String)
  found = [] of String
  parser.each_node { |node| found << node.kind.to_s }
  found
end

describe Noir::PhpBlockParser do
  it "builds if/elseif/else, try/catch/finally, switch and loop nodes past strings and heredocs" do
    src = <<-PHP
      <?php
      if ($a === "}") { $x = '{'; } elseif (! $b) foo(); else { bar(); }
      try { $s = <<<EOT
      } {
      EOT;
      } catch (Exception $e) {} finally { baz(); }
      switch ($k) { case 'a': if ($c) { d(); } break; default: e(); }
      foreach ($xs as $x) while ($y) { do { z(); } while (false); }
      PHP
    parser = Noir::PhpBlockParser.new(src)
    kinds(parser).should eq(%w[If Elseif Else Try Catch Finally Switch Case If Case Foreach While Do])
    first = parser.root.children.first
    parser.lexer.source(first.head.not_nil!).should eq(%q($a === "}"))
    parser.root.children[1].prev.should eq(first)
    parser.root.children[2].prev.should eq(parser.root.children[1])
  end

  it "finds closures, arrow functions and match inside expressions and conditions" do
    src = %(<?php\nif (collect($x)->first(function ($v) use ($w) { return $v; })) { $f = fn ($a) => $a + 1; $m = match ($q) { 1 => fn () => 2, default => 3 }; }\n)
    parser = Noir::PhpBlockParser.new(src)
    kinds(parser).should eq(%w[If Closure ArrowFn Match ArrowFn])
    closure = parser.root.children.first.children.first
    parser.lexer.source(closure.uses.not_nil!).should eq("$w")
    # A node inside the closure has the if and the closure as ancestors.
    parser.path(src.index!("return")).map(&.kind.to_s).should eq(%w[If Closure])
  end

  it "reads class members, attributes and their targets" do
    src = <<-PHP
      <?php
      #[Route('/p'), IsGranted('X')]
      final class C extends B {
          use T;
          const A = 1;
          #[Route('/a', methods: ['GET'])]
          public function a(#[CurrentUser] $u) { $o = new class { public function inner() {} }; }
          public static ?int $n = null, $m;
          abstract protected function b(): void;
      }
      PHP
    parser = Noir::PhpBlockParser.new(src)
    klass = parser.declarations.first
    klass.name.should eq("C")
    klass.attributes.map(&.name).should eq(%w[Route IsGranted])
    members = klass.children
    members.map(&.kind.to_s).should eq(%w[Method Property Method])
    members[0].name.should eq("a")
    members[0].attributes.map(&.name).should eq(%w[Route])
    members[1].modifiers.should eq(%w[public static])
    members[2].braced?.should be_false
    parser.attributes.map(&.name).should eq(%w[Route IsGranted Route CurrentUser])
  end

  it "reads alternative-syntax bodies to their end word and braced namespaces as blocks" do
    src = <<-PHP
      <?php
      namespace AppX {
          if ($a):
              foo();
              if (! $u) { bar(); }
          elseif ($b):
              baz();
          else:
              foreach ($xs as $x): qux(); endforeach;
          endif;
          if (! class_exists(C::class)) { class C { public function m() {} } }
          class D {}
      }
      PHP
    parser = Noir::PhpBlockParser.new(src)
    block = parser.root.children.first
    block.kind.should eq(Noir::PhpBlockParser::Kind::Block)
    block.children.map(&.kind.to_s).should eq(%w[If Elseif Else If Class])
    block.children[0].children.map(&.kind.to_s).should eq(%w[If])
    block.children[2].children.map(&.kind.to_s).should eq(%w[Foreach])
    parser.declarations.map(&.name).should eq(%w[C D])
  end

  it "splits array literals into key/value entries" do
    src = %(<?php\n$a = ['prefix' => 'x', /* 'c' => 1, */ 'mw' => ['auth', 'v'], fn () => 1, 'k' => fn ($a) => [$a, 2]];\n)
    parser = Noir::PhpBlockParser.new(src)
    entries = parser.array_entries(src.index!('[')).not_nil!
    entries.map { |e| e.key.try { |k| parser.lexer.source(k) } }.should eq(["'prefix'", "'mw'", nil, "'k'"])
    entries.map { |e| parser.lexer.source(e.value) }.should eq(["'x'", "['auth', 'v']", "fn () => 1", "fn ($a) => [$a, 2]"])
  end

  it "stays linear on deep chains and long files" do
    small = "<?php\n" + (1..2_000).join { |i| "if ($a#{i}) { $f = function () { return fn () => match ($x) { 1 => 2 }; }; } else { foo(); }\n" }
    large = "<?php\n" + (1..16_000).join { |i| "if ($a#{i}) { $f = function () { return fn () => match ($x) { 1 => 2 }; }; } else { foo(); }\n" }
    small_time = Time.measure { Noir::PhpBlockParser.new(small) }
    large_time = Time.measure { Noir::PhpBlockParser.new(large).root.children.size.should eq(32_000) }
    large_time.should be < (small_time * 24 + 1.second)
  end
end
