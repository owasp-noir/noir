package MyApp::Controller::Api;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub status ($c) {
  my $status = StatusService->current;
  return $c->render(json => $status);
}

sub login ($c) {
  my $payload = LoginService::authenticate($c->param('username'));
  return $c->render(json => $payload);
}

1;
