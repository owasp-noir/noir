package MyApp;
use Mojo::Base 'Mojolicious', -signatures;

# Mojo::UserAgent client calls (full URLs with `://`) must never be
# mistaken for server routes — and example code inside POD must stay
# outside the analyzer's reach.
sub fetch ($self) {
  my $ua = $self->ua;
  $ua->get('https://example.com/upstream')->result;
}

sub startup ($self) {
  my $r = $self->routes;

  $r->get('/api/status')->to('api#status');
  $r->post('/api/login')->to('api#login');
  $r->any([qw(GET POST)] => '/api/sync')->to('api#sync');
  $r->websocket('/api/socket')->to('api#socket');
  $r->route('/api/legacy')->via('GET')->to('api#legacy');

  # Real-world Mojolicious plugins (e.g. Mojolicious::Plugin::Minion::Admin)
  # group routes under a `$prefix` returned by `routes->any('/prefix')`.
  my $admin = $r->any('/admin');
  $admin->get('/users')->to('admin#list_users');
  $admin->post('/users')->to('admin#create_user');
  $admin->get('/users/:id')->to('admin#show_user');

  # Nested under for deeper prefix propagation: `/admin` + `/audit` + leaf.
  my $audit = $admin->under('/audit');
  $audit->get('/logs')->to('admin/audit#logs');

  # Inline chain: `->under('/v2')->get('/health')` without a named var.
  $r->under('/v2')->get('/health')->to('api/v2#health');
}

1;

=encoding utf8

=head1 NAME

MyApp - example app used by the Mojolicious analyzer fixture.

=head1 SYNOPSIS

  # Example wiring shown inside POD — must NOT be picked up as a real route.
  my $r = $app->routes;
  $r->get('/should-not-appear-in-pod')->to('pod#sample');
  $r->post('/another-pod-fake')->to('pod#fake');

=cut
