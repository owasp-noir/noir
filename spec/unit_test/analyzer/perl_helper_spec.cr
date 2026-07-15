require "../../spec_helper"
require "../../../src/analyzer/analyzers/perl/perl_helper"

describe Analyzer::Perl::Helper do
  describe ".underscore" do
    it "inserts underscores between lowercase/digit and uppercase runs" do
      Analyzer::Perl::Helper.underscore("FooBar").should eq("foo_bar")
      Analyzer::Perl::Helper.underscore("fooBarBaz").should eq("foo_bar_baz")
      Analyzer::Perl::Helper.underscore("abc123Def").should eq("abc123_def")
    end

    it "leaves already-underscored names unchanged apart from downcasing" do
      Analyzer::Perl::Helper.underscore("already_fine").should eq("already_fine")
      Analyzer::Perl::Helper.underscore("ALLCAPS").should eq("allcaps")
    end
  end
end
