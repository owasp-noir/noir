package MyApp::Controller::API;
use Moose;
BEGIN { extends 'Catalyst::Controller::REST' }

sub status : GET : Path('/api/status') : Args(0) {
    my ($self, $c) = @_;
}

sub item : Path('/api/item') : Args(1) : ActionClass('REST') {
    my ($self, $c, $id) = @_;
}

sub item_GET {
    my ($self, $c) = @_;
    my $verbose = $c->req->query_parameters->{'verbose'};
}

sub item_POST {
    my ($self, $c) = @_;
    my $name = $c->request->body_parameters->{'name'};
    my $metadata = $c->request->body_data->{'metadata'};
}

sub report_GET : Path('/explicit-get') : Args(0) {
    my ($self, $c) = @_;
}

1;
