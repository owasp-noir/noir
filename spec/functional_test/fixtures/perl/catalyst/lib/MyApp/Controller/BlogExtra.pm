package MyApp::Controller::BlogExtra;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

sub comments : Chained('/blog/root') PathPart('comments') Args(0) {
    my ($self, $c) = @_;
}

1;
