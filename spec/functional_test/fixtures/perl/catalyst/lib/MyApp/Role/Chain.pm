package MyApp::Role::Chain;
use Moose::Role;

# Intermediate chain links only (all CaptureArgs) — never dispatched on their
# own. A controller composes them and sets `setup`'s PathPart via config,
# mirroring App::Manoc::ControllerRole::ResultSet.
sub setup : Chained('/') CaptureArgs(0) PathPart('set.in.config') { }

sub base : Chained('setup') PathPart('') CaptureArgs(0) { }

sub object : Chained('base') PathPart('') CaptureArgs(1) { }

1;
