package MyApp::Controller::Users;
use Moose;
BEGIN { extends 'Catalyst::Controller' }

sub list : Local : Args(0) {
    my ($self, $c) = @_;
    my $q = $c->req->query_params->{'q'};
}

sub profile : Path('profile') : Args(1) {
    my ($self, $c, $id) = @_;
    my $user = $c->req->headers->header('X-User');
}

sub user : Chained('/') : PathPart('users') : CaptureArgs(1) {
    my ($self, $c, $id) = @_;
}

sub edit : Chained('user') : PathPart('edit') : Args(0) {
    my ($self, $c) = @_;
    my $display_name = $c->req->body_params->{'display_name'};
}

sub update : PUT : Chained('user') : PathPart('') : Args(0) {
    my ($self, $c) = @_;
    my $display_name = $c->request->body_parameters->{'display_name'};
}

1;
