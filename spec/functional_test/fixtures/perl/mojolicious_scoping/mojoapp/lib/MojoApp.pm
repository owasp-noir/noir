package MojoApp;
use Mojo::Base 'Mojolicious', -signatures;

sub startup ($self) {
    my $r = $self->routes;
    $r->get('/real')->to('thing#index');

    my $admin = $r->under('/admin')->to('auth#check');
    $admin->get('/panel')->to('admin#panel');

    # None of these are routes. They are ordinary accessors that happen to
    # be spelled `->get('literal')`: a Mojo::Cache lookup, a stash read, and
    # a config read. A string key is the *common* shape for all three.
    my $ttl  = $cache->get("session_timeout");
    my $user = $self->stash->get("current_user");
    my $key  = $self->config->get("secret_name");
}

1;
