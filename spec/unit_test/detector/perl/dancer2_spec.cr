require "../../../spec_helper"
require "../../../../src/detector/detectors/perl/*"

describe "Detect Perl Dancer2" do
  options = create_test_options
  instance = Detector::Perl::Dancer2.new options

  it "detects Dancer2 in cpanfile" do
    cpanfile = <<-PERL
      requires 'perl', '5.020';
      requires 'Dancer2', '>= 1.0.0';
      requires 'DBI';
      PERL

    instance.detect("cpanfile", cpanfile).should be_true
  end

  it "detects Dancer2 in Makefile.PL" do
    makefile = <<-PERL
      use ExtUtils::MakeMaker;
      WriteMakefile(
        NAME => 'MyApp',
        PREREQ_PM => {
          'Dancer2' => '1.0.0',
        },
      );
      PERL

    instance.detect("Makefile.PL", makefile).should be_true
  end

  it "detects `use Dancer2` in a .pl file" do
    app = <<-PERL
      use Dancer2;

      get '/' => sub { 'Hello!' };

      dance;
      PERL

    instance.detect("bin/app.pl", app).should be_true
  end

  it "detects a Dancer2 app package in a .pm file" do
    pkg = <<-PERL
      package MyApp;
      use Dancer2;

      get '/ping' => sub { 'pong' };

      1;
      PERL

    instance.detect("lib/MyApp.pm", pkg).should be_true
  end

  it "detects a Dancer2 plugin module" do
    plugin = <<-PERL
      package Dancer2::Plugin::Custom;
      use Dancer2::Plugin;

      1;
      PERL

    instance.detect("lib/Dancer2/Plugin/Custom.pm", plugin).should be_true
  end

  it "does not detect plain Perl files" do
    plain = <<-'PERL'
      use strict;
      use warnings;

      sub hello { print "hi\n" }
      hello();
      PERL

    instance.detect("script/plain.pl", plain).should be_false
  end

  it "does not detect Dancer (v1) source" do
    dancer1 = <<-PERL
      use Dancer;

      get '/' => sub { 'Hello!' };

      dance;
      PERL

    instance.detect("bin/app.pl", dancer1).should be_false
  end

  it "does not detect cpanfile without Dancer2" do
    cpanfile = <<-PERL
      requires 'DBI';
      requires 'JSON';
      PERL

    instance.detect("cpanfile", cpanfile).should be_false
  end
end
