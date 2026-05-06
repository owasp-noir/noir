require "../../../spec_helper"
require "../../../../src/detector/detectors/perl/*"

describe "Detect Perl Mojolicious" do
  options = create_test_options
  instance = Detector::Perl::Mojolicious.new options

  it "detects Mojolicious in cpanfile" do
    cpanfile = <<-PERL
      requires 'perl', '5.020';
      requires 'Mojolicious', '>= 9.0';
      requires 'DBI';
      PERL

    instance.detect("cpanfile", cpanfile).should be_true
  end

  it "detects Mojolicious in Makefile.PL" do
    makefile = <<-PERL
      use ExtUtils::MakeMaker;
      WriteMakefile(
        NAME => 'MyApp',
        PREREQ_PM => {
          'Mojolicious' => '9.0',
        },
      );
      PERL

    instance.detect("Makefile.PL", makefile).should be_true
  end

  it "detects Mojolicious::Lite in .pl file" do
    lite = <<-PERL
      use Mojolicious::Lite -signatures;

      get '/' => sub ($c) { $c->render(text => 'Hello!') };

      app->start;
      PERL

    instance.detect("script/myapp.pl", lite).should be_true
  end

  it "detects Mojolicious controller in .pm file" do
    controller = <<-PERL
      package MyApp::Controller::Foo;
      use Mojo::Base 'Mojolicious::Controller', -signatures;

      sub welcome ($c) {
        $c->render(text => 'Welcome');
      }

      1;
      PERL

    instance.detect("lib/MyApp/Controller/Foo.pm", controller).should be_true
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

  it "does not detect cpanfile without Mojolicious" do
    cpanfile = <<-PERL
      requires 'DBI';
      requires 'JSON';
      PERL

    instance.detect("cpanfile", cpanfile).should be_false
  end
end
