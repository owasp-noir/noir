require "spec"
require "../../../src/utils/c_comments"

describe Noir::CComments do
  it "blanks line and block comments but keeps strings and offsets" do
    source = %(final x = 1; // note\nfinal s = "a // b"; /* c */ final y = 2;)
    stripped = Noir::CComments.strip(source)
    stripped.bytesize.should eq source.bytesize
    stripped.includes?("note").should be_false
    stripped.includes?("/* c */").should be_false
    stripped.includes?("a // b").should be_true
  end

  # An unterminated `/*` used to stop one character short: the file's last
  # character was never blanked and fell through verbatim. A letter leaking
  # out is harmless; the two that matter are not. A bare `'` opens a string
  # state for everything the caller scans afterwards, and a `}` is counted
  # as real by the brace matchers this helper feeds.
  it "blanks an unterminated block comment to the end of input" do
    {"final x = 1; /* note x", "final x = 1; /* note '", "final x = 1; /* note }"}.each do |source|
      stripped = Noir::CComments.strip(source)
      stripped.size.should eq source.size
      stripped.should eq "final x = 1; " + " " * (source.size - 13)
    end
  end

  it "still consumes a block comment that ends exactly at end of input" do
    source = "final x = 1; /* note */"
    stripped = Noir::CComments.strip(source)
    stripped.size.should eq source.size
    stripped.should eq "final x = 1; " + " " * (source.size - 13)
  end

  it "lets the final character of an unterminated block through with leak_unterminated_tail" do
    Noir::CComments.strip("x; /* note }", leak_unterminated_tail: true).should eq "x; " + " " * 8 + "}"
  end

  it "treats only the given quotes as string openers" do
    Noir::CComments.strip(%(a = '//' "b"), quotes: %(")).should eq "a = '" + " " * 7
  end
end
