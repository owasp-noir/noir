use strict;
use warnings;
use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
    '%c %o',
    ['verbose!' => 'be verbose (negatable)'],
    ['count+'   => 'increase verbosity'],
);

print "ok\n" if $opt->verbose;
