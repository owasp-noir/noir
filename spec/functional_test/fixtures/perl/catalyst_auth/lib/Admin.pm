package MyApp::Controller::Admin;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

# Application-wide guard for this controller: Catalyst runs `auto` before
# every action, so an auth check here protects the whole controller.
sub auto :Private {
    my ( $self, $c ) = @_;
    $c->detach('/login') unless $c->user_exists;
    return 1;
}

sub list :Local {
    my ( $self, $c ) = @_;
    return;
}

1;
