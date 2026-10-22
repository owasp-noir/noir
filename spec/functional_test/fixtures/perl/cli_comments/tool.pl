#!/usr/bin/perl
use strict;
use Getopt::Long;

my ($real, $old);
# GetOptions("old" => \$old);
GetOptions("real" => \$real); # "trailing" => \$old
$ENV{SET_ONLY} = 'x';
my $home = $ENV{READ_ME};
my $last = $#ARGV;

=pod

Set $ENV{DOC_ONLY} to tune it.

=cut

__END__
$ENV{AFTER_END}
