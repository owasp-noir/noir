package MyApp::Role::Crud;
use Moose::Role;

# A CRUD action carried by a Moose role. Its `Chained('object')` parent is
# supplied by whichever controller composes the role at runtime, so within
# this package the chain has no resolvable root. The analyzer must treat it
# as an incomplete chain fragment and NOT invent a phantom top-level
# `/purge` route (the real path is `/<controller>/<id>/purge`, which needs
# runtime role composition static analysis cannot perform).
sub purge : Chained('object') PathPart('purge') Args(0) {
    my ( $self, $c ) = @_;
    $c->stash( purged => 1 );
}

1;
