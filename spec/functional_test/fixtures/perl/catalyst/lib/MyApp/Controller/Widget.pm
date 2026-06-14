package MyApp::Controller::Widget;
use Moose;
BEGIN { extends 'Catalyst::Controller' }
with 'MyApp::Role::Resource';

# `setup` (carried by Role::Chain) gets its real PathPart here, so the composed
# chain resolves to `/widgets` and `/widgets/<id>/delete`.
__PACKAGE__->config(
    action => {
        setup => { PathPart => 'widgets' },
    },
);

1;
