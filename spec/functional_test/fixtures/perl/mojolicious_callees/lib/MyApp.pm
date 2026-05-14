package MyApp;
use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {
  my $r = $self->routes;

  $r->get('/api/status')->to('api#status');
  $r->post('/api/login')->to('api#login');
  $r->get('/admin/users/:id')->to('admin/users#show');
  $r->post('/admin/users')->to(controller => 'admin/users', action => 'create');
}

1;
