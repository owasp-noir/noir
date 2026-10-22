require "../../spec_helper"
require "../../../src/analyzer/analyzers/cfml/coldbox"

describe "Analyzer::Cfml::Coldbox::LOCAL_STRING_RE" do
  # PCRE used to retry from every offset inside a long word run, so a
  # 100 KB run in front of ordinary router code took seconds (quadratic).
  it "stays linear on a long identifier run" do
    source = "x" * 100_000 + "\n route(\"/a\").to(\"main.index\"); }"
    elapsed = Time.measure { source.matches?(Analyzer::Cfml::Coldbox::LOCAL_STRING_RE) }
    elapsed.should be < 1.second
  end

  it "still captures locals, including after a dot or a glued `var`" do
    locals = [] of String
    "var prefix = \"/a\"; this.base = '/b'; xvar y = \"/c\";".scan(Analyzer::Cfml::Coldbox::LOCAL_STRING_RE) { |m| locals << m[1] }
    locals.should eq(["prefix", "base", "y"])
  end
end
