package MyApp;
use MooX::Options;

option 'verbose' => (
    is  => 'ro',
    doc => 'be verbose',
);

option 'name' => (
    is       => 'ro',
    format   => 's',
    required => 1,
    doc      => 'name to use',
);

my $token = $ENV{API_TOKEN};

sub run {
    my ($self) = @_;
    print "$token\n" if $self->verbose;
    print $self->name, "\n";
}

__PACKAGE__->new_with_options->run;

1;
