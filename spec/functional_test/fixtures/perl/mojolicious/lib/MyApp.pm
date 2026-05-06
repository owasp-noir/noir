package MyApp;
use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {
  my $r = $self->routes;

  $r->get('/api/status')->to('api#status');
  $r->post('/api/login')->to('api#login');
  $r->any([qw(GET POST)] => '/api/sync')->to('api#sync');
  $r->websocket('/api/socket')->to('api#socket');
  $r->route('/api/legacy')->via('GET')->to('api#legacy');
}

1;
