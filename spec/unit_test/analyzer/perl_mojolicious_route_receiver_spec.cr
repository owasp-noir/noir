require "../../spec_helper"
require "../../../src/analyzer/analyzers/perl/mojolicious"

def mojolicious_routes(analyzer : Analyzer::Perl::Mojolicious, source : String) : Array(String)
  analyzer.analyze_content(source, "MyApp.pm").map { |endpoint| "#{endpoint.method} #{endpoint.url}" }
end

# `analyze_content` is the level the receiver gate has to be exercised at:
# it is what builds the route-variable set that `route_receiver?` consults.
describe Analyzer::Perl::Mojolicious do
  analyzer = Analyzer::Perl::Mojolicious.new(create_test_options)

  it "keeps every shape of real Mojolicious route" do
    source = <<-PERL
      package MyApp;
      use Mojo::Base 'Mojolicious', -signatures;

      sub startup ($self) {
        $self->routes->post('/chain/self')->to('a#b');
        my $r = $self->routes;
        $r->get('/plain')->to('a#b');
        $r->websocket('/ws')->to('a#b');
        $r->route('/legacy')->via('GET')->to('a#b');
        my $auth = $r->under('/auth')->to('auth#check');
        $auth->get('')->to('auth#index');
        $auth->get('/me')->to('auth#me');
        $r->under('/v2')->get('/health')->to('h#ok');
      }

      sub _mount ($router) {
        $router->get('/inner')->to('m#inner');
      }
      PERL

    found = mojolicious_routes(analyzer, source)
    found.should contain("POST /chain/self")
    found.should contain("GET /plain")
    found.should contain("GET /ws")
    found.should contain("GET /legacy")
    found.should contain("GET /auth")
    found.should contain("GET /auth/me")
    found.should contain("GET /v2/health")
    found.should contain("GET /inner")
  end

  it "does not read a data accessor with a string key as a route" do
    source = <<-PERL
      package MyApp;
      use Mojo::Base 'Mojolicious', -signatures;

      sub startup ($self) {
        my $r = $self->routes;
        $r->get('/real')->to('a#b');
        my $ttl  = $cache->get("session_timeout");
        my $user = $self->stash->get("current_user");
        my $page = $c->req->query_params->get('page');
        my $any  = $registry->any('/not-a-route');
        my $rt   = $store->route('/not-a-route-either');
      }
      PERL

    mojolicious_routes(analyzer, source).should eq(["GET /real"])
  end

  it "ignores a Perl file that is not Mojolicious at all" do
    source = <<-PERL
      package Dancer2App;
      use Dancer2;

      prefix '/api';

      get '/status' => sub {
        my $page = query_parameters->get('page');
        return { ok => 1 };
      };
      PERL

    mojolicious_routes(analyzer, source).should be_empty
  end
end
