package MyApp::Controller::Root;
use Moose;
BEGIN { extends 'Catalyst::Controller'; }

sub root :Chained('/') :PathPart('a') :CaptureArgs(1) {
}

sub item :Chained('root') :PathPart('item') :Args(0) {
}

__PACKAGE__->meta->make_immutable;
1;
