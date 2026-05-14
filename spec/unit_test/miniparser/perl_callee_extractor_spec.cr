require "spec"
require "../../../src/miniparsers/perl_callee_extractor"

describe Noir::PerlCalleeExtractor do
  it "extracts Perl bare, qualified, and method callees" do
    body = <<-PERL
      my $user = UserService::load($c->param('id'));
      Audit->write('users');
      $c->render(json => $user);
      print "debug";
      PERL

    callees = Noir::PerlCalleeExtractor.callees_for_body(body, "app.pl", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService::load", 10},
      {"c.param", 10},
      {"Audit.write", 11},
      {"c.render", 12},
    ])
  end

  it "extracts sub bodies and skips nested anonymous sub bodies" do
    source = <<-PERL
      get '/echo' => sub ($c) {
        $c->on(message => sub ($c, $msg) {
          HiddenService::nested($msg);
          $c->send($msg);
        });
        EchoService::accepted();
      };
      PERL

    sub_start = source.index!("sub")
    body = Noir::PerlCalleeExtractor.extract_sub_after(source, sub_start)
    body.should_not be_nil

    body.try do |body_text, start_line|
      start_line.should eq(1)
      Noir::PerlCalleeExtractor.callees_for_body(body_text, "app.pl", start_line).map { |name, _, line| {name, line} }.should eq([
        {"c.on", 2},
        {"EchoService::accepted", 6},
      ])
    end
  end

  it "does not index fake subs from comments or quoted strings" do
    source = <<-PERL
      # sub ghost { Ghost.call() }
      my $text = q{sub hidden { Hidden.call() }};

      sub status ($c) {
        return StatusService->current;
      }
      PERL

    bodies = Noir::PerlCalleeExtractor.named_sub_bodies(source, "Api.pm")
    bodies.keys.sort!.should eq(["status"])
    status = bodies["status"]
    Noir::PerlCalleeExtractor.callees_for_body(status[:body], status[:path], status[:start_line]).map(&.[0]).should eq([
      "StatusService.current",
    ])
  end

  it "indexes Mojolicious controller action callees" do
    source = <<-PERL
      package MyApp::Controller::Api;
      use Mojo::Base 'Mojolicious::Controller', -signatures;

      sub status ($c) {
        my $status = StatusService->current;
        return $c->render(json => $status);
      }
      PERL

    callees = Noir::PerlCalleeExtractor.controller_action_callees(source, "Api.pm")
    callees.keys.sort!.should eq(["api#status"])
    callees["api#status"].map { |name, _, line| {name, line} }.should eq([
      {"StatusService.current", 5},
      {"c.render", 6},
    ])
  end

  it "indexes nested Mojolicious controller namespaces without collapsing them" do
    source = <<-PERL
      package MyApp::Controller::Admin::Users;
      use Mojo::Base 'Mojolicious::Controller', -signatures;

      sub show ($c) {
        return Admin::UserService->find($c->param('id'));
      }
      PERL

    callees = Noir::PerlCalleeExtractor.controller_action_callees(source, "Admin/Users.pm")
    callees.keys.sort!.should eq(["admin/users#show"])
    callees["admin/users#show"].map { |name, _, line| {name, line} }.should eq([
      {"Admin.UserService.find", 5},
      {"c.param", 5},
    ])
    callees.has_key?("users#show").should be_false
  end
end
