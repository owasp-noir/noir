package MyApp::Controller::Api;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub status ($c) {
  my $payload = AService->call;
  return $c->render(json => $payload);
}

1;
