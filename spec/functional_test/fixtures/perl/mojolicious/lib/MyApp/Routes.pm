package MyApp::Routes;
use Mojo::Base 'Mojolicious', -signatures;

# Neither of these is a route: a `Mojo::Cache` lookup whose key interpolates
# a scalar (`$id`), and a scheme-less `Mojo::UserAgent` request to a host.
sub helpers ($self) {
  my $id    = $self->param('id');
  my $cache = $self->cache;
  $cache->get("entry:$id");
  my $ua = $self->ua;
  $ua->get('fastapi.example.org/v1/ping')->result;
}

sub wire ($self) {
  my $r = $self->routes;

  # The route base lives in a scalar, then `$r->any($test_path)` consumes it.
  # Angle-bracket placeholders (`<testid:num>`, `<name>`) normalize to the
  # sigil form, and an empty leaf (`get('')`) is the prefix itself.
  my $test_path = '/tests/<testid:num>';
  my $test_r    = $r->any($test_path);
  $test_r->get('')->to('test#show');
  $test_r->get('/status')->to('test#status');
  $test_r->get('/modules/<name>')->to('test#module');

  # `my $var` and its `= ...` split across two physical lines.
  my $api = $r->under('/api/v1');
  my $api_admin
    = $api->under('/')->to('Auth#admin');
  $api_admin->post('jobs')->to('job#create');
  $api_admin->delete('jobs/<jobid:num>')->to('job#destroy');
}

1;
