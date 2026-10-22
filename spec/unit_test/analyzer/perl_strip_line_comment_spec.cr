require "../../spec_helper"
require "../../../src/analyzer/engines/perl_engine"

private def strip(line : String) : String
  Analyzer::Perl::PerlEngine.strip_line_comment(line)
end

describe "Analyzer::Perl::PerlEngine.strip_line_comment" do
  it "cuts a real comment" do
    strip(%q(GetOptions("real" => \$r); # "old" => \$o)).should eq(%q(GetOptions("real" => \$r); ))
    strip("# whole line").should eq("")
    strip("my $x = 1;# tight").should eq("my $x = 1;")
  end

  it "keeps `#` in strings and the $#array sigil" do
    line = %q(my $u = "a#b" . 'c#d' . $#arr . $#{$ref}; my $y = $ENV{AFTER};)
    strip(line).should eq(line)
  end

  it "reads quote-like operators with `#` delimiters through every delimiter" do
    [
      %q((my $p = $0) =~ s#^.*/##; my $y = $ENV{AFTER_SUBST};),
      %q($s =~ tr###; my $y = $ENV{AFTER_TR};),
      %q($s =~ y#a#b#; my $y = $ENV{AFTER_Y};),
      %q(if ($s =~ m#a/b#) { my $y = $ENV{AFTER_M}; }),
      %q(my $re = qr#x#i; my $y = $ENV{AFTER_QR};),
      %q(my @w = qw#a b#; my $y = $ENV{AFTER_QW};),
      %q(my $q = q{a#b}; my $y = $ENV{AFTER_BRACES};),
      %q($s =~ s{#}{x}g; my $y = $ENV{AFTER_BRACKET_SUBST};),
      %q($s =~ s{a} {#}; my $y = $ENV{AFTER_SPACED_BRACKET};),
      %q(if ($s =~ /[^#]+/) { my $y = $ENV{AFTER_REGEX}; }),
    ].each do |line|
      strip(line).should eq(line)
    end
  end

  it "still cuts a comment after a closed quote-like operator" do
    strip(%q($s =~ s#a#b#g; # $ENV{COMMENTED})).should eq(%q($s =~ s#a#b#g; ))
  end

  it "does not take a variable, hash key or method named like an operator for one" do
    strip(%q(my $s = $h{s} + $o->s; # c)).should eq(%q(my $s = $h{s} + $o->s; ))
    strip(%q(my %h = (s => 1, y => 2); # c)).should eq(%q(my %h = (s => 1, y => 2); ))
  end

  it "stays linear on hostile lines" do
    line = "s{" * 50_000 + " # c"
    elapsed = Time.measure { strip(line) }
    elapsed.should be < 1.second
    strip(" / #" * 50_000).size.should be > 0
  end
end
