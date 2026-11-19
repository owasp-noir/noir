require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

def perl_auth_tag_for(path, line, options, tech = "perl_dancer2")
  details = Details.new(PathInfo.new(path, line))
  details.technology = tech
  endpoint = Endpoint.new("/x", "GET", [] of Param, details)
  PerlAuthTagger.new(options).perform([endpoint])
  endpoint
end

describe "PerlAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/perl/dancer2_auth", __DIR__)
  app_path = "#{fixture_base}/lib/MyApp.pm"
  guarded_path = "#{fixture_base}/lib/Guarded.pm"

  # lib/MyApp.pm line reference:
  #  5: get '/admin'    => require_role Admin => sub {
  #  9: get '/me'       => require_login sub {
  # 13: post '/reports' => require_any_role ['Admin', 'Auditor'] => sub {
  # 17: get '/dashboard' => sub {           # body calls logged_in_user
  # 23: get '/public'   => sub {            # no guard

  it "detects the Dancer2 require_role wrapper" do
    endpoint = perl_auth_tag_for(app_path, 5, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("perl_auth")
    endpoint.tags[0].description.should contain("require_role")
  end

  it "detects the Dancer2 require_login wrapper" do
    endpoint = perl_auth_tag_for(app_path, 9, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_login")
  end

  it "detects the Dancer2 require_any_role wrapper" do
    endpoint = perl_auth_tag_for(app_path, 13, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_any_role")
  end

  it "detects logged_in_user inside the handler body" do
    endpoint = perl_auth_tag_for(app_path, 17, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("logged_in_user")
  end

  it "leaves unguarded routes untagged" do
    endpoint = perl_auth_tag_for(app_path, 23, create_test_options)
    endpoint.tags.empty?.should be_true
  end

  it "detects an application-wide `hook before` guard" do
    endpoint = perl_auth_tag_for(guarded_path, 10, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("hook before")
  end

  # 29: get '/subscription' =>
  # 30:     require_login sub {
  it "follows a multi-line wrapper past a path containing `sub`" do
    endpoint = perl_auth_tag_for(app_path, 29, create_test_options)
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("require_login")
  end

  it "labels a Catalyst `sub auto` global guard as Catalyst, not Dancer2" do
    catalyst_path = File.expand_path("../../../functional_test/fixtures/perl/catalyst_auth/lib/Admin.pm", __DIR__)
    endpoint = perl_auth_tag_for(catalyst_path, 13, create_test_options, "perl_catalyst")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("Catalyst")
    endpoint.tags[0].description.should_not contain("Dancer2")
  end

  it "needs a refusal before a user read or a login call counts as a guard" do
    dir = File.tempname("noir_perl_read")
    Dir.mkdir_p(dir)
    app = File.join(dir, "App.pm")
    File.write(app, <<-PL)
      use Dancer2;

      get '/' => sub {
          my $content = "home";
          if (my $user = logged_in_user()) {
              $content .= "hi";
          }
          return $content;
      };

      post '/login' => sub {
          my ($ok) = authenticate_user(body_parameters->get('username'), body_parameters->get('password'));
          return $ok ? 'ok' : 'no';
      };

      get '/reports' => sub {
          send_error('Forbidden', 403) unless user_has_role('Admin');
          return 'reports';
      };
      PL

    begin
      home = perl_auth_tag_for(app, 3, create_test_options)
      login = perl_auth_tag_for(app, 11, create_test_options)
      reports = perl_auth_tag_for(app, 16, create_test_options)
      home.tags.should be_empty
      login.tags.should be_empty
      reports.tags.map(&.description).should eq(["Protected by Dancer2 user_has_role"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "does not take a send_error unrelated to the caller as a refusal" do
    dir = File.tempname("noir_perl_send_error")
    Dir.mkdir_p(dir)
    app = File.join(dir, "App.pm")
    File.write(app, <<-PL)
      use Dancer2;

      post '/comment' => sub {
          my $name = logged_in_user ? logged_in_user->{name} : 'guest';
          send_error('missing body', 400) unless body_parameters->get('body');
          return "thanks $name";
      };
      PL

    begin
      perl_auth_tag_for(app, 3, create_test_options).tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "counts sign-in redirects and refusals conditioned on the caller read" do
    dir = File.tempname("noir_perl_conditioned")
    Dir.mkdir_p(dir)
    app = File.join(dir, "App.pm")
    File.write(app, <<-PL)
      use Dancer2;
      get '/a' => sub {
          return redirect uri_for('/signin') unless logged_in_user;
      };
      get '/b' => sub {
          halt('go away') unless logged_in_user;
      };
      get '/c' => sub {
          die "not authorized" unless user_has_role('admin');
      };
      get '/d' => sub {
          return unless logged_in_user;
      };
      get '/e' => sub ($c) {
          return $c->reply->not_found unless $c->is_user_authenticated;
      };
      get '/f' => sub ($c) {
          $c->detach('/error') unless $c->check_user_roles('admin');
      };
      get '/g' => sub {
          pass unless logged_in_user;
      };
      PL

    begin
      guarded = {2, 5, 8, 11, 14, 17}.map { |line| perl_auth_tag_for(app, line, create_test_options) }
      guarded.each(&.tags.map(&.name).should(eq(["auth"])))
      perl_auth_tag_for(app, 20, create_test_options).tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "skips CSRF, CORS and maintenance bridges" do
    dir = File.tempname("noir_perl_bridge_negatives")
    Dir.mkdir_p(File.join(dir, "lib/MyApp/Controller"))
    app = File.join(dir, "lib/MyApp.pm")
    File.write(app, <<-PL)
      package MyApp;
      sub startup ($self) {
          my $r = $self->routes;
          my $csrf = $r->under('/')->to('gate#csrf');
          my $cors = $r->under('/api')->to('gate#cors');
          my $maint = $r->under('/')->to('gate#maintenance');
          my $rev = $r->under('/')->to(action => 'ensure_user', controller => 'gate');
          $csrf->post('/c')->to('x#c');
          $cors->get('/cors')->to('x#cors');
          $maint->get('/m')->to('x#m');
          $rev->get('/rev')->to('x#rev');
      }
      1;
      PL
    File.write(File.join(dir, "lib/MyApp/Controller/Gate.pm"), <<-PL)
      package MyApp::Controller::Gate;
      sub ensure_user ($c) {
          return 1 if $c->session('user_id');
          $c->redirect_to('login');
          return undef;
      }
      sub csrf ($c) {
          return 1 if ($c->req->headers->header('X-CSRF-Token') // '') eq $c->csrf_token;
          $c->render(text => 'Bad CSRF token', status => 400);
          return undef;
      }
      sub cors ($c) {
          $c->res->headers->header('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
          if ($c->req->method eq 'OPTIONS') {
              $c->rendered(204);
              return undef;
          }
          return 1;
      }
      sub maintenance ($c) {
          return $c->render(template => 'maintenance', status => 503) if $c->config->{maintenance};
          $c->stash(user => $c->current_user);
          return 1;
      }
      1;
      PL

    begin
      CodeLocator.instance.clear_all
      Dir.glob("#{dir}/**/*.pm").each { |file| CodeLocator.instance.register_path(file) }
      options = create_test_options
      options["base"] = YAML::Any.new(dir)
      csrf, cors, maint, rev = {8, 9, 10, 11}.map { |line| perl_auth_tag_for(app, line, options, "perl_mojolicious") }
      csrf.tags.should be_empty
      cors.tags.should be_empty
      maint.tags.should be_empty
      rev.tags.map(&.description).should eq(["Protected by Mojolicious under gate#ensure_user"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end

  it "applies a Mojolicious full-app `under` bridge to the routes built on it" do
    dir = File.tempname("noir_perl_bridge")
    Dir.mkdir_p(File.join(dir, "lib/MyApp/Controller"))
    app = File.join(dir, "lib/MyApp.pm")
    File.write(app, <<-PL)
      package MyApp;
      use Mojo::Base 'Mojolicious', -signatures;
      sub startup ($self) {
          my $r = $self->routes;
          my $logged_in = $r->under('/')->to('session#ensure_user');
          my $maybe = $r->under('/')->to('session#maybe_user');
          my $api = $r->any('/api');
          my $api_admin
            = $api->under('/')->to(controller => 'Auth', action => 'admin_only');
          $r->get('/login')->to('session#login');
          $logged_in->get('/account')->to('account#show');
          my $settings = $logged_in->any('/settings');
          $settings->get('/')->to('settings#index');
          $maybe->get('/feed')->to('feed#index');
          $api_admin->post('/users')->to('user#create');
      }
      1;
      PL
    File.write(File.join(dir, "lib/MyApp/Controller/Session.pm"), <<-PL)
      package MyApp::Controller::Session;
      sub ensure_user ($self) { $self->current_user ? 1 : $self->_redirect_login }
      sub maybe_user ($self) {
          $self->stash(user => $self->current_user);
          return 1;
      }
      sub _redirect_login ($self) {
          $self->redirect_to('login');
          return undef;
      }
      1;
      PL
    File.write(File.join(dir, "lib/MyApp/Controller/Auth.pm"), <<-PL)
      package MyApp::Controller::Auth;
      sub admin_only ($self) {
          return 1 if $self->_is_admin;
          $self->render(json => {error => 'Forbidden'}, status => 403);
          return 0;
      }
      sub _is_admin ($self) {
          my $user = $self->current_user or return 0;
          return $user->is_admin;
      }
      1;
      PL

    begin
      CodeLocator.instance.clear_all
      Dir.glob("#{dir}/**/*.pm").each { |file| CodeLocator.instance.register_path(file) }
      options = create_test_options
      options["base"] = YAML::Any.new(dir)
      login, account, settings, feed, users = {10, 11, 13, 14, 15}.map { |line| perl_auth_tag_for(app, line, options, "perl_mojolicious") }
      login.tags.should be_empty
      account.tags.map(&.description).should eq(["Protected by Mojolicious under session#ensure_user"])
      settings.tags.map(&.description).should eq(["Protected by Mojolicious under session#ensure_user"])
      feed.tags.should be_empty
      users.tags.map(&.description).should eq(["Protected by Mojolicious under Auth#admin_only"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end

  it "applies a Mojolicious::Lite `under` guard to the routes after it, not before" do
    dir = File.tempname("noir_perl_under")
    Dir.mkdir_p(dir)
    app = File.join(dir, "app.pl")
    File.write(app, <<-PL)
      use Mojolicious::Lite -signatures;

      get '/' => sub ($c) {
        $c->render(text => 'public');
      };

      under sub ($c) {
        return 1 if $c->is_user_authenticated;
        $c->redirect_to('/login');
        return undef;
      };

      get '/secret' => sub ($c) {
        $c->render(text => 'secret');
      };
      PL

    begin
      public_route = perl_auth_tag_for(app, 3, create_test_options, "perl_mojolicious")
      secret = perl_auth_tag_for(app, 13, create_test_options, "perl_mojolicious")
      public_route.tags.should be_empty
      secret.tags.map(&.description).should eq(["Protected by Mojolicious is_user_authenticated"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
