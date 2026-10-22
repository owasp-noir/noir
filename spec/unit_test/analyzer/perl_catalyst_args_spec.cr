require "../../spec_helper"
require "../../../src/analyzer/analyzers/perl/catalyst"

describe Analyzer::Perl::Catalyst do
  analyzer = Analyzer::Perl::Catalyst.new(create_test_options)

  it "collapses a hostile :Args count to one wildcard instead of building N segments" do
    source = <<-PERL
      package MyApp::Controller::Root;
      use Moose;
      BEGIN { extends 'Catalyst::Controller' }
      sub big :Path('big') :Args(2000000000) { }
      sub two :Path('two') :Args(2) { }
      1;
      PERL

    found = analyzer.analyze_content(source, "lib/MyApp/Controller/Root.pm")
    urls = found.map(&.url)
    urls.should contain("/big/:arg")
    urls.should contain("/two/:arg1/:arg2")
  end
end
