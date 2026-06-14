package MyApp::Role::Resource;
use Moose::Role;
with 'MyApp::Role::Chain';

# Terminal CRUD actions. Their `base`/`object` parents live in Role::Chain, so
# standalone they cannot resolve (and are skipped) — only once composed into a
# controller does the chain close. Mirrors ControllerRole::CommonCRUD.
sub list : Chained('base') PathPart('') Args(0) {
    my ( $self, $c ) = @_;
}

sub remove : Chained('object') PathPart('delete') Args(0) {
    my ( $self, $c ) = @_;
}

1;
