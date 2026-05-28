package MyApp::Controller::Admin;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

__PACKAGE__->config(namespace => 'manage', path => 'ops');

sub index : Index : Args(0) {
    my ($self, $c) = @_;
}

sub dashboard : Local : Args(0) {
    my ($self, $c) = @_;
}

sub item : Method('POST') : Path('item') : Args(1) {
    my ($self, $c) = @_;
}

sub preflight : OPTION : Path('/preflight') : Args(0) {
    my ($self, $c) = @_;
}

1;
