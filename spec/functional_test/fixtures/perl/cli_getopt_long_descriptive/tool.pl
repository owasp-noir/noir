use strict;
use warnings;
use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['verbose|v' => 'be verbose'],
    ['name=s'    => 'name to use'],
    ['help'      => 'print usage', {shortcircuit => 1}],
);

my $token = $ENV{API_TOKEN};
my $first = $ARGV[0];

print $usage->text if $opt->help;
print "$token $first\n" if $opt->verbose;
