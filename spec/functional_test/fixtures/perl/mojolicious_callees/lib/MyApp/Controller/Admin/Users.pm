package MyApp::Controller::Admin::Users;
use Mojo::Base 'Mojolicious::Controller', -signatures;

sub show ($c) {
  my $user = Admin::UserService->find($c->param('id'));
  return $c->render(json => $user);
}

sub create ($c) {
  my $user = Admin::UserService->create($c->param('name'));
  return $c->render(json => $user);
}

1;
