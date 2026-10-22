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

  it "does not lex a heredoc body as code" do
    source = <<-PERL
      get '/hello' => sub ($c) {
        my $html = <<'HTML';
      <div class="x"> } don't stop
      HTML
        AlphaService::build();
        $c->render(text => $html);
      };
      PERL

    sub_start = source.index!("sub")
    body = Noir::PerlCalleeExtractor.extract_sub_after(source, sub_start)
    body.should_not be_nil

    body.try do |body_text, start_line|
      Noir::PerlCalleeExtractor.callees_for_body(body_text, "app.pl", start_line).map(&.[0]).should eq([
        "AlphaService::build",
        "c.render",
      ])
    end
  end

  it "masks interpolating and bare heredocs and keeps line numbers" do
    source = <<-PERL
      sub render ($c) {
        my $a = <<"ONE";
      value { $c->wrong('x')
      ONE
        my $b = <<TWO;
      more } text
      TWO
        RealService::run();
      }
      PERL

    bodies = Noir::PerlCalleeExtractor.named_sub_bodies(source, "App.pm")
    bodies.keys.should eq(["render"])
    render = bodies["render"]
    Noir::PerlCalleeExtractor.callees_for_body(render[:body], render[:path], render[:start_line])
      .map { |name, _, line| {name, line} }.should eq([{"RealService::run", 8}])
  end

  it "masks an indented <<~ heredoc whose terminator is indented" do
    source = <<-PERL
      sub greet ($c) {
          my $text = <<~END;
              hi } there don't stop
              END
          IndentService::run();
      }
      PERL

    bodies = Noir::PerlCalleeExtractor.named_sub_bodies(source, "App.pm")
    greet = bodies["greet"]
    Noir::PerlCalleeExtractor.callees_for_body(greet[:body], greet[:path], greet[:start_line])
      .map(&.[0]).should eq(["IndentService::run"])
  end

  it "does not treat a left shift as a heredoc" do
    source = <<-PERL
      sub bits ($c) {
        my $mask = $x << 2;
        my $wide = 1 << MAX;
        ShiftService::run();
      }
      PERL

    Noir::PerlCalleeExtractor.strip_non_code(source).should eq(source)

    bodies = Noir::PerlCalleeExtractor.named_sub_bodies(source, "App.pm")
    bits = bodies["bits"]
    Noir::PerlCalleeExtractor.callees_for_body(bits[:body], bits[:path], bits[:start_line])
      .map(&.[0]).should eq(["ShiftService::run"])
  end

  it "blanks an unterminated heredoc to EOF instead of looping" do
    source = <<-PERL
      sub broken ($c) {
        my $html = <<'NEVER';
      dangling } body '
        LostService::run();
      }
      PERL

    stripped = Noir::PerlCalleeExtractor.strip_non_code(source)
    stripped.lines.size.should eq(source.lines.size)
    stripped.includes?("LostService").should be_false
    Noir::PerlCalleeExtractor.named_sub_bodies(source, "App.pm").should be_empty
  end

  it "treats $# as the last-index sigil, not a comment" do
    source = <<-'PERL'
      get '/last' => sub ($c) { my $n = $#{$c->stash('items')}; BetaService::run(); $c->render(text => $n); };
      PERL

    sub_start = source.index!("sub")
    body = Noir::PerlCalleeExtractor.extract_sub_after(source, sub_start)
    body.should_not be_nil

    body.try do |body_text, start_line|
      Noir::PerlCalleeExtractor.callees_for_body(body_text, "app.pl", start_line).map(&.[0]).should eq([
        "c.stash",
        "BetaService::run",
        "c.render",
      ])
    end
  end

  it "still treats a real # as a comment" do
    source = <<-PERL
      sub notes ($c) {
        my $last = $#items; # Ghost::call();
        NoteService::run();
      }
      PERL

    bodies = Noir::PerlCalleeExtractor.named_sub_bodies(source, "App.pm")
    notes = bodies["notes"]
    Noir::PerlCalleeExtractor.callees_for_body(notes[:body], notes[:path], notes[:start_line])
      .map(&.[0]).should eq(["NoteService::run"])
  end
end
