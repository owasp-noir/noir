package MyApp::Controller::Blog;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

sub root : Chained('/') PathPart('blog') CaptureArgs(1) {
    my ($self, $c, $slug) = @_;
}

sub show : Chained('root') PathPart('') Args(0) {
    my ($self, $c) = @_;
}

sub archive : Chained('root') PathPart Args(0) {
    my ($self, $c) = @_;
}

1;
