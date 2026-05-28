package MyApp::Controller::Root;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

__PACKAGE__->config(namespace => '');

sub index : Path : Args(0) {
    my ($self, $c) = @_;
    my $page = $c->req->param('page');
}

sub about : Path('/about') : Args(0) {
    my ($self, $c) = @_;
}

sub health : Global : Args(0) {
    my ($self, $c) = @_;
}

1;
