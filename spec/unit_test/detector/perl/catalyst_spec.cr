require "../../../spec_helper"
require "../../../../src/detector/detectors/perl/*"

describe "Detect Perl Catalyst" do
  options = create_test_options
  instance = Detector::Perl::Catalyst.new options

  it "detects Catalyst in cpanfile" do
    cpanfile = <<-PERL
      requires 'Catalyst::Runtime', '5.90132';
      requires 'Catalyst::Controller::REST';
      PERL

    instance.detect("cpanfile", cpanfile).should be_true
  end

  it "detects Catalyst in Makefile.PL" do
    makefile = <<-PERL
      use ExtUtils::MakeMaker;
      WriteMakefile(
        NAME => 'MyApp',
        PREREQ_PM => {
          'Catalyst' => '5.90',
        },
      );
      PERL

    instance.detect("Makefile.PL", makefile).should be_true
  end

  it "detects Catalyst application modules" do
    app = <<-PERL
      package MyApp;
      use Moose;
      use Catalyst qw/ConfigLoader Static::Simple/;
      __PACKAGE__->setup;
      PERL

    instance.detect("lib/MyApp.pm", app).should be_true
  end

  it "detects Catalyst controllers" do
    controller = <<-PERL
      package MyApp::Controller::Users;
      use Moose;
      BEGIN { extends 'Catalyst::Controller' }
      sub index : Path Args(0) {}
      PERL

    instance.detect("lib/MyApp/Controller/Users.pm", controller).should be_true
  end

  it "detects CatalystX::Routes usage" do
    routes = <<-PERL
      package MyApp::Controller::Api;
      use CatalystX::Routes;
      PERL

    instance.detect("lib/MyApp/Controller/Api.pm", routes).should be_true
  end

  it "does not detect plain Perl files" do
    plain = <<-'PERL'
      use strict;
      use warnings;
      sub hello { print "hi\n" }
      PERL

    instance.detect("script/plain.pl", plain).should be_false
  end
end
