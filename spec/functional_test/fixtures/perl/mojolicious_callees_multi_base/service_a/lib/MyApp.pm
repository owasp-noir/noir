package MyApp;
use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {
  my $r = $self->routes;
  $r->get('/a/status')->to('api#status');
}

1;
